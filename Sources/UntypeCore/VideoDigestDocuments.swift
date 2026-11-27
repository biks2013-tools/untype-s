import Foundation
import ImageIO

/// The digest as documents (plan-080): a self-contained HTML page (the
/// default; images embedded) and, on request, a Word document with the same
/// content and images.
public struct VideoDigestDocument: Sendable {
    public var video: VideoInfo
    public var analysis: VideoDigestAnalysis
    public var source: VideoTranscriptSource
    /// The JPEG of each screenshot, by its `moment.screenshot` path.
    public var images: [String: Data]
    public var thumbnail: Data?
    public var made: Date

    public init(video: VideoInfo, analysis: VideoDigestAnalysis, source: VideoTranscriptSource, images: [String: Data], thumbnail: Data?, made: Date = Date()) {
        self.video = video
        self.analysis = analysis
        self.source = source
        self.images = images
        self.thumbnail = thumbnail
        self.made = made
    }

    var basisNote: String {
        let shots = analysis.moments.contains { $0.screenshot != nil }
            ? "Screenshots taken from the video at the moments listed."
            : "No screenshots: the moments link to their place in the video."
        return "Made by untype on \(Self.dateText(made)) from \(source.description). Machine transcripts can get names and numbers wrong: check them before quoting. \(shots)"
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy, HH:mm"
        return formatter.string(from: date)
    }

    func link(_ seconds: Int) -> String {
        YouTubeVideo.watchURL(video.id, at: seconds)
    }

    // MARK: - HTML

    public func html() -> String {
        let a = analysis
        var toc: [(String, String)] = [("points", "Key points"), ("how", "How it is said")]
        var body = ""

        body += "<section id=\"points\"><h2>Key points</h2><ol class=\"points\">"
        for point in a.keyPoints {
            body += "<li><strong>\(esc(point.lead))</strong> \(esc(point.text))\(point.time.map { " " + ts($0) } ?? "")</li>"
        }
        body += "</ol></section>"

        body += "<section id=\"how\"><h2>How it is said</h2><p>\(esc(a.delivery.summary))</p><dl class=\"how\">"
        body += "<dt>Tone</dt><dd>\(esc(a.delivery.tone))</dd><dt>Structure</dt><dd>\(esc(a.delivery.structure))</dd>"
        if !a.delivery.techniques.isEmpty {
            body += "<dt>Techniques</dt><dd><ul>" + a.delivery.techniques.map { "<li>\(esc($0))</li>" }.joined() + "</ul></dd>"
        }
        body += "<dt>Evidence</dt><dd>\(esc(a.delivery.evidence))</dd></dl></section>"

        if !a.moments.isEmpty {
            toc.append(("moments", "Reference moments"))
            body += "<section id=\"moments\"><h2>Reference moments</h2><div class=\"moments\">"
            for moment in a.moments {
                body += "<figure class=\"moment\">"
                if let path = moment.screenshot, let data = images[path] {
                    body += "<a href=\"\(esc(link(moment.time)))\" target=\"_blank\" rel=\"noopener\"><img src=\"data:image/jpeg;base64,\(data.base64EncodedString())\" alt=\"\(esc(moment.title))\"></a>"
                }
                body += "<figcaption>\(ts(moment.time)) <strong>\(esc(moment.title))</strong><br>\(esc(moment.why))</figcaption></figure>"
            }
            body += "</div></section>"
        }

        for (index, section) in a.sections.enumerated() {
            let id = "s\(index + 1)"
            toc.append((id, section.title))
            body += "<section id=\"\(id)\"><h2>\(esc(section.title)) \(ts(section.start))</h2>"
            body += section.paragraphs.map { "<p>\(esc($0))</p>" }.joined() + "</section>"
        }

        if !a.quotes.isEmpty {
            toc.append(("quotes", "Quotes"))
            body += "<section id=\"quotes\"><h2>Quotes</h2>"
            for quote in a.quotes {
                body += "<blockquote><p>“\(esc(quote.text))”</p>"
                if let translation = quote.translation, !translation.isEmpty {
                    body += "<p class=\"translation\">\(esc(translation))</p>"
                }
                body += "<footer>\(quote.speaker.map { esc($0) + " · " } ?? "")\(ts(quote.time))</footer></blockquote>"
            }
            body += "</section>"
        }

        if !a.resources.isEmpty {
            toc.append(("resources", "Links"))
            body += "<section id=\"resources\"><h2>Links</h2><ul>" + a.resources.map { "<li><a href=\"\(esc($0.url))\" target=\"_blank\" rel=\"noopener\">\(esc($0.title))</a></li>" }.joined() + "</ul></section>"
        }

        let thumb = thumbnail.map { "data:image/jpeg;base64,\($0.base64EncodedString())" } ?? video.thumbnailURL
        let speakers = a.speakers.isEmpty ? "" : "<span>\(esc(a.speakers.joined(separator: ", ")))</span>"
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(a.title))</title>
        <style>
        :root{--bg:#f8f9fb;--fg:#1d2330;--muted:#5d6676;--card:#ffffff;--border:#dfe3ea;--accent:#2f62d8;--accent-dim:#e8eefc}
        @media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#12151c;--fg:#e6e9ef;--muted:#9aa3b2;--card:#1a1f29;--border:#2a3140;--accent:#7aa2ff;--accent-dim:#1e2a45}}
        :root[data-theme="dark"]{--bg:#12151c;--fg:#e6e9ef;--muted:#9aa3b2;--card:#1a1f29;--border:#2a3140;--accent:#7aa2ff;--accent-dim:#1e2a45}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
        a{color:var(--accent)}
        .hero{text-align:center;padding:2.5rem 1.25rem 2rem;border-bottom:1px solid var(--border)}
        .kicker{font-size:12px;letter-spacing:.18em;text-transform:uppercase;color:var(--muted);font-weight:600;margin-bottom:.8rem}
        .hero h1{margin:0 auto .6rem;max-width:900px;font-size:clamp(24px,3.6vw,34px);line-height:1.25}
        .standfirst{max-width:800px;margin:0 auto 1.4rem;color:var(--muted)}
        .hero-thumb{max-width:640px;margin:0 auto 1rem;border-radius:12px;overflow:hidden;box-shadow:0 8px 28px rgba(0,0,0,.25)}
        .hero-thumb img{width:100%;display:block}
        .hero-meta{display:flex;gap:1rem;flex-wrap:wrap;justify-content:center;font-size:14px;color:var(--muted)}
        .container{display:flex;gap:2rem;max-width:1180px;margin:0 auto;padding:1.5rem 1.25rem 3rem}
        .toc{position:sticky;top:1rem;align-self:flex-start;width:240px;flex:none;font-size:14px;background:var(--card);border:1px solid var(--border);border-radius:10px;padding:.75rem 1rem}
        .toc ol{padding-left:1.1rem;margin:.4rem 0}.toc a{color:var(--muted);text-decoration:none}.toc a:hover{color:var(--accent)}
        main{min-width:0;flex:1}
        section{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.1rem 1.4rem;margin-bottom:1.25rem}
        h2{font-size:21px;margin:.2rem 0 .8rem}
        a.ts{font-size:13px;font-variant-numeric:tabular-nums;text-decoration:none;background:var(--accent-dim);border-radius:6px;padding:.05rem .4rem;white-space:nowrap}
        .points li{margin-bottom:.55rem}
        .how dt{font-weight:600;margin-top:.6rem}.how dd{margin:0 0 .2rem}
        .moments{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:1rem}
        .moment{margin:0}.moment img{width:100%;border-radius:8px;display:block;border:1px solid var(--border)}
        .moment figcaption{font-size:14px;margin-top:.45rem;color:var(--muted)}.moment strong{color:var(--fg)}
        blockquote{margin:0 0 1rem;padding:.2rem 1rem;border-left:3px solid var(--accent)}
        blockquote p{margin:.3rem 0}.translation{color:var(--muted);font-size:15px}blockquote footer{font-size:13px;color:var(--muted)}
        .basis{font-size:13px;color:var(--muted);max-width:1180px;margin:0 auto;padding:0 1.25rem 2rem}
        .theme{position:fixed;right:1rem;bottom:1rem;border:1px solid var(--border);background:var(--card);color:var(--fg);border-radius:20px;padding:.35rem .8rem;cursor:pointer}
        @media (max-width:820px){.container{flex-direction:column}.toc{position:static;width:100%}}
        </style></head><body>
        <header class="hero">
        <div class="kicker">Video digest · \(esc(video.channel))</div>
        <h1>\(esc(a.title))</h1>
        <p class="standfirst">\(esc(a.standfirst))</p>
        <div class="hero-thumb"><a href="\(esc(video.url))" target="_blank" rel="noopener"><img src="\(esc(thumb))" alt="\(esc(video.title))"></a></div>
        <div class="hero-meta"><span><a href="\(esc(video.url))" target="_blank" rel="noopener">\(esc(video.title))</a></span><span>\(VideoDigestTime.label(video.durationSeconds))</span>\(speakers)</div>
        </header>
        <div class="container">
        <nav class="toc"><strong>Contents</strong><ol>\(toc.map { "<li><a href=\"#\($0.0)\">\(esc($0.1))</a></li>" }.joined())</ol></nav>
        <main>\(body)</main>
        </div>
        <p class="basis">\(esc(basisNote))</p>
        <button class="theme" onclick="var r=document.documentElement;var d=r.getAttribute('data-theme')==='dark'||(!r.getAttribute('data-theme')&&matchMedia('(prefers-color-scheme: dark)').matches);r.setAttribute('data-theme',d?'light':'dark')">Light / dark</button>
        </body></html>
        """
    }

    private func ts(_ seconds: Int) -> String {
        "<a class=\"ts\" href=\"\(esc(link(seconds)))\" target=\"_blank\" rel=\"noopener\">\(VideoDigestTime.label(seconds))</a>"
    }

    private func esc(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - DOCX

    public func docx() throws -> Data {
        var paragraphs: [String] = []
        var relationships: [String] = []
        var media: [(String, Data)] = []
        var nextID = 10

        func addLink(_ url: String) -> String {
            nextID += 1
            relationships.append("<Relationship Id=\"rId\(nextID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(xml(url))\" TargetMode=\"External\"/>")
            return "rId\(nextID)"
        }
        func run(_ text: String, bold: Bool = false, italic: Bool = false, color: String? = nil, size: Int? = nil) -> String {
            var properties = ""
            if bold { properties += "<w:b/>" }
            if italic { properties += "<w:i/>" }
            if let color { properties += "<w:color w:val=\"\(color)\"/>" }
            if let size { properties += "<w:sz w:val=\"\(size)\"/>" }
            return "<w:r>\(properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>")<w:t xml:space=\"preserve\">\(xml(text))</w:t></w:r>"
        }
        func hyperlink(_ text: String, _ url: String) -> String {
            "<w:hyperlink r:id=\"\(addLink(url))\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:t xml:space=\"preserve\">\(xml(text))</w:t></w:r></w:hyperlink>"
        }
        func time(_ seconds: Int) -> String {
            hyperlink("[\(VideoDigestTime.label(seconds))]", link(seconds))
        }
        func paragraph(_ content: String, style: String? = nil) {
            paragraphs.append("<w:p>\(style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? "")\(content)</w:p>")
        }
        func image(_ data: Data, name: String) {
            nextID += 1
            let id = "rId\(nextID)"
            let file = "image\(media.count + 1).jpeg"
            media.append((file, data))
            relationships.append("<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(file)\"/>")
            let (width, height) = Self.pixelSize(data) ?? (1600, 900)
            let cx = 5_760_720 // 6.3 in
            let cy = Int(Double(cx) * Double(height) / Double(max(1, width)))
            let number = media.count
            paragraph("""
            <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(number)" name="\(xml(name))"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="\(number)" name="\(file)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
            """)
        }

        let a = analysis
        paragraph(run(a.title), style: "Title")
        paragraph(hyperlink(video.title, video.url) + run(" · \(video.channel) · \(VideoDigestTime.label(video.durationSeconds))", color: "5D6676"))
        if let thumbnail { image(thumbnail, name: "Thumbnail") }
        paragraph(run(a.standfirst, italic: true))

        paragraph(run("Key points"), style: "Heading1")
        for point in a.keyPoints {
            paragraph(run(point.lead + " ", bold: true) + run(point.text) + (point.time.map { " " + time($0) } ?? ""), style: "ListBullet")
        }

        paragraph(run("How it is said"), style: "Heading1")
        paragraph(run(a.delivery.summary))
        paragraph(run("Tone: ", bold: true) + run(a.delivery.tone))
        paragraph(run("Structure: ", bold: true) + run(a.delivery.structure))
        for technique in a.delivery.techniques {
            paragraph(run(technique), style: "ListBullet")
        }
        paragraph(run("Evidence: ", bold: true) + run(a.delivery.evidence))

        if !a.moments.isEmpty {
            paragraph(run("Reference moments"), style: "Heading1")
            for moment in a.moments {
                paragraph(time(moment.time) + run(" " + moment.title, bold: true), style: "Heading2")
                if let path = moment.screenshot, let data = images[path] { image(data, name: moment.title) }
                paragraph(run(moment.why))
            }
        }

        for section in a.sections {
            paragraph(run(section.title + " ") + time(section.start), style: "Heading1")
            for text in section.paragraphs { paragraph(run(text)) }
        }

        if !a.quotes.isEmpty {
            paragraph(run("Quotes"), style: "Heading1")
            for quote in a.quotes {
                paragraph(run("“\(quote.text)”", italic: true), style: "Quote")
                if let translation = quote.translation, !translation.isEmpty { paragraph(run(translation, color: "5D6676"), style: "Quote") }
                paragraph(run((quote.speaker.map { $0 + " · " } ?? ""), color: "5D6676", size: 18) + time(quote.time), style: "Quote")
            }
        }

        if !a.resources.isEmpty {
            paragraph(run("Links"), style: "Heading1")
            for resource in a.resources { paragraph(hyperlink(resource.title, resource.url), style: "ListBullet") }
        }
        paragraph(run(basisNote, color: "5D6676", size: 18))

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>\(paragraphs.joined())<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
        var zip = ZipStoreWriter()
        zip.add("[Content_Types].xml", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
        """.utf8))
        zip.add("_rels/.rels", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """.utf8))
        zip.add("word/_rels/document.xml.rels", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\(relationships.joined())</Relationships>
        """.utf8))
        zip.add("word/styles.xml", Data(Self.styles.utf8))
        zip.add("word/document.xml", Data(document.utf8))
        for (file, data) in media {
            zip.add("word/media/\(file)", data)
        }
        return zip.finish()
    }

    private func xml(_ text: String) -> String {
        esc(text).replacingOccurrences(of: "'", with: "&apos;")
    }

    static func pixelSize(_ data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }

    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
    <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="200"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="320" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="1F3A7A"/><w:sz w:val="30"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="360" w:hanging="240"/></w:pPr></w:style>
    <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="567"/></w:pPr></w:style>
    <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="2F62D8"/><w:u w:val="single"/></w:rPr></w:style>
    </w:styles>
    """
}

/// A zip archive with stored (uncompressed) entries: enough for a .docx.
struct ZipStoreWriter {
    private var data = Data()
    private var central = Data()
    private var count: UInt16 = 0

    mutating func add(_ name: String, _ content: Data) {
        let nameData = Data(name.utf8)
        let crc = Self.crc32(content)
        let offset = UInt32(data.count)
        var local = Data()
        local.append(le32(0x04034b50)); local.append(le16(20)); local.append(le16(0x0800)); local.append(le16(0))
        local.append(le16(0)); local.append(le16(0x21)) // time, date (1980-01-01)
        local.append(le32(crc)); local.append(le32(UInt32(content.count))); local.append(le32(UInt32(content.count)))
        local.append(le16(UInt16(nameData.count))); local.append(le16(0))
        local.append(nameData)
        data.append(local)
        data.append(content)
        var entry = Data()
        entry.append(le32(0x02014b50)); entry.append(le16(20)); entry.append(le16(20)); entry.append(le16(0x0800)); entry.append(le16(0))
        entry.append(le16(0)); entry.append(le16(0x21))
        entry.append(le32(crc)); entry.append(le32(UInt32(content.count))); entry.append(le32(UInt32(content.count)))
        entry.append(le16(UInt16(nameData.count))); entry.append(le16(0)); entry.append(le16(0)); entry.append(le16(0)); entry.append(le16(0))
        entry.append(le32(0)); entry.append(le32(offset))
        entry.append(nameData)
        central.append(entry)
        count += 1
    }

    func finish() -> Data {
        var out = data
        let offset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0)); out.append(le16(count)); out.append(le16(count))
        out.append(le32(UInt32(central.count))); out.append(le32(offset)); out.append(le16(0))
        return out
    }

    private func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
