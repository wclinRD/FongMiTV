import Foundation
import Network

@MainActor
final class DLNAService: ObservableObject {
    @Published var devices: [DLNADevice] = []
    @Published var isSearching = false

    struct DLNADevice: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var location: String
        var usn: String
    }

    func search(timeout: TimeInterval = 4) async {
        isSearching = true
        devices = []
        defer { isSearching = false }

        let endpoint = NWEndpoint.hostPort(host: "239.255.255.250", port: 1900)
        let connection = NWConnection(to: endpoint, using: .udp)
        let queue = DispatchQueue(label: "dlna")
        connection.start(queue: queue)

        let msg = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 3\r
        ST: ssdp:all\r
        \r

        """
        connection.send(content: msg.data(using: .utf8), completion: .contentProcessed { _ in })

        // Receive responses for timeout
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let data = await withCheckedContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    cont.resume(returning: data)
                }
            }
            if let data, let text = String(data: data, encoding: .utf8) {
                if let dev = parseResponse(text) {
                    if !devices.contains(where: { $0.location == dev.location }) {
                        devices.append(dev)
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        connection.cancel()
    }

    private func parseResponse(_ text: String) -> DLNADevice? {
        var location: String?
        var usn: String?
        var name: String?
        for line in text.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "location": location = val
            case "usn": usn = val
            case "server": if name == nil { name = val }
            default: break
            }
        }
        guard let loc = location else { return nil }
        return DLNADevice(name: name ?? "DLNA Device", location: loc, usn: usn ?? "")
    }

    /// Send a basic AVTransport SetAVTransportURI + Play to a device control URL.
    func play(on device: DLNADevice, url: String) async {
        // Fetch device description to find AVTransport control URL (simplified: assume /upnp/control/AVTransport)
        guard let base = URL(string: device.location) else { return }
        let controlURL = base.deletingLastPathComponent().appendingPathComponent("upnp/control/AVTransport")
        let soap = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(url)</CurrentURI>
              <CurrentURIMetaData></CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
        var req = URLRequest(url: controlURL)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"", forHTTPHeaderField: "SOAPACTION")
        req.httpBody = soap.data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
        // Play
        let playSoap = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Speed>1</Speed>
            </u:Play>
          </s:Body>
        </s:Envelope>
        """
        var playReq = URLRequest(url: controlURL)
        playReq.httpMethod = "POST"
        playReq.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        playReq.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#Play\"", forHTTPHeaderField: "SOAPACTION")
        playReq.httpBody = playSoap.data(using: .utf8)
        _ = try? await URLSession.shared.data(for: playReq)
    }
}
