import Foundation

/// Minimal .xlsx writer: sheets of text/number cells with a handful of styles (Xlsx.java).
/// The zip is written by hand (stored, no compression): iOS has no public zip API.
final class Xlsx {
    static let normal = 0, header = 1, title = 2, section = 3, time = 4, dec = 5, bold = 6

    enum Value {
        case text(String)
        case number(Double)
    }

    struct Cell {
        let v: Value
        let style: Int
    }

    final class Sheet {
        let name: String
        var rows: [[Cell?]] = []
        var widths: [Int] = []

        init(_ name: String) { self.name = name }

        @discardableResult
        func row(_ cells: [Any?]) -> Sheet { styled(Xlsx.normal, cells) }

        @discardableResult
        func styled(_ style: Int, _ cells: [Any?]) -> Sheet {
            rows.append(cells.map { Xlsx.cell($0, style) })
            return self
        }

        func blank() { rows.append([]) }

        func setWidths(_ w: [Int]) { widths = w }
    }

    static func cell(_ o: Any?, _ style: Int) -> Cell? {
        switch o {
        case nil: return nil
        case let c as Cell: return c
        case let d as Double: return Cell(v: .number(d), style: style)
        case let i as Int: return Cell(v: .number(Double(i)), style: style)
        case let s as String: return Cell(v: .text(s), style: style)
        default: return Cell(v: .text("\(o!)"), style: style)
        }
    }

    static func c(_ v: Any, _ style: Int) -> Cell { cell(v, style)! }

    /// Seconds as an Excel time cell (shown as m:ss.00).
    static func timeCell(_ seconds: Double) -> Cell {
        seconds > 0 ? Cell(v: .number(seconds / 86400), style: time) : Cell(v: .text(""), style: normal)
    }

    private(set) var sheets: [Sheet] = []
    private var names = Set<String>()

    func sheet(_ name: String) -> Sheet {
        var n = name.replacingOccurrences(of: "[\\[\\]:*?/\\\\]", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if n.isEmpty { n = "List" }
        if n.count > 28 { n = String(n.prefix(28)) }
        let base = n
        var i = 2
        while names.contains(n.lowercased()) {
            n = "\(base) \(i)"
            i += 1
        }
        names.insert(n.lowercased())
        let s = Sheet(n)
        sheets.append(s)
        return s
    }

    func data() -> Data {
        var files: [(String, String)] = []
        var ct = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
            + "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        for i in sheets.indices {
            ct += "<Override PartName=\"/xl/worksheets/sheet\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        ct += "</Types>"
        files.append(("[Content_Types].xml", ct))
        files.append(("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
            + "</Relationships>"))
        var wb = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"
        var rels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for (i, s) in sheets.enumerated() {
            wb += "<sheet name=\"\(Xlsx.esc(s.name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
            rels += "<Relationship Id=\"rId\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i + 1).xml\"/>"
        }
        wb += "</sheets></workbook>"
        rels += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        rels += "</Relationships>"
        files.append(("xl/workbook.xml", wb))
        files.append(("xl/_rels/workbook.xml.rels", rels))
        files.append(("xl/styles.xml", Xlsx.styles))
        for (i, s) in sheets.enumerated() { files.append(("xl/worksheets/sheet\(i + 1).xml", Xlsx.sheetXml(s))) }
        return Zip.stored(files.map { ($0.0, Data($0.1.utf8)) })
    }

    private static let styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        + "<numFmts count=\"1\"><numFmt numFmtId=\"164\" formatCode=\"[m]:ss.00\"/></numFmts>"
        + "<fonts count=\"5\">"
        + "<font><sz val=\"11\"/><color rgb=\"FF171A1D\"/><name val=\"Calibri\"/></font>"
        + "<font><b/><sz val=\"11\"/><color rgb=\"FFFFFFFF\"/><name val=\"Calibri\"/></font>"
        + "<font><b/><sz val=\"18\"/><color rgb=\"FF171A1D\"/><name val=\"Calibri\"/></font>"
        + "<font><b/><sz val=\"13\"/><color rgb=\"FFFF6257\"/><name val=\"Calibri\"/></font>"
        + "<font><b/><sz val=\"11\"/><color rgb=\"FF171A1D\"/><name val=\"Calibri\"/></font>"
        + "</fonts>"
        + "<fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill>"
        + "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF171A1D\"/><bgColor indexed=\"64\"/></patternFill></fill></fills>"
        + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"7\">"
        + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
        + "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\"/>"
        + "<xf numFmtId=\"0\" fontId=\"2\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
        + "<xf numFmtId=\"0\" fontId=\"3\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
        + "<xf numFmtId=\"164\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>"
        + "<xf numFmtId=\"2\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>"
        + "<xf numFmtId=\"0\" fontId=\"4\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
        + "</cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"

    private static func sheetXml(_ s: Sheet) -> String {
        var b = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        if !s.widths.isEmpty {
            b += "<cols>"
            for (i, w) in s.widths.enumerated() { b += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(w)\" customWidth=\"1\"/>" }
            b += "</cols>"
        }
        b += "<sheetData>"
        for (r, row) in s.rows.enumerated() {
            b += "<row r=\"\(r + 1)\">"
            for (ci, cell) in row.enumerated() {
                guard let cell = cell else { continue }
                let ref = col(ci) + "\(r + 1)"
                switch cell.v {
                case .number(let d):
                    if !d.isFinite { continue }
                    b += "<c r=\"\(ref)\" s=\"\(cell.style)\"><v>\(JSON.numberText(d))</v></c>"
                case .text(let t):
                    if t.isEmpty && cell.style == normal { continue }
                    b += "<c r=\"\(ref)\" s=\"\(cell.style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(t))</t></is></c>"
                }
            }
            b += "</row>"
        }
        b += "</sheetData></worksheet>"
        return b
    }

    static func col(_ i0: Int) -> String {
        var s = ""
        var i = i0 + 1
        while i > 0 {
            let m = (i - 1) % 26
            s = String(UnicodeScalar(UInt8(65 + m))) + s
            i = (i - 1) / 26
        }
        return s
    }

    private static func esc(_ s: String) -> String {
        var b = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": b += "&amp;"
            case "<": b += "&lt;"
            case ">": b += "&gt;"
            case "\"": b += "&quot;"
            default: if ch.value >= 0x20 || ch == "\n" || ch == "\t" { b.unicodeScalars.append(ch) }
            }
        }
        return b
    }
}

/// A plain zip archive with stored (uncompressed) entries.
enum Zip {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    static func stored(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        func u16(_ v: Int, _ d: inout Data) { var x = UInt16(truncatingIfNeeded: v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32, _ d: inout Data) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        // 1980-01-01 00:00 in DOS format
        let dosTime = 0, dosDate = (0 << 9) | (1 << 5) | 1
        for (name, body) in files {
            let n = Data(name.utf8)
            let crc = crc32(body)
            let offset = UInt32(out.count)
            u32(0x04034B50, &out)
            u16(20, &out); u16(0x0800, &out); u16(0, &out); u16(dosTime, &out); u16(dosDate, &out)
            u32(crc, &out); u32(UInt32(body.count), &out); u32(UInt32(body.count), &out)
            u16(n.count, &out); u16(0, &out)
            out.append(n)
            out.append(body)
            u32(0x02014B50, &central)
            u16(20, &central); u16(20, &central); u16(0x0800, &central); u16(0, &central); u16(dosTime, &central); u16(dosDate, &central)
            u32(crc, &central); u32(UInt32(body.count), &central); u32(UInt32(body.count), &central)
            u16(n.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
            u32(0, &central); u32(offset, &central)
            central.append(n)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        u32(0x06054B50, &out)
        u16(0, &out); u16(0, &out); u16(files.count, &out); u16(files.count, &out)
        u32(UInt32(central.count), &out); u32(cdOffset, &out); u16(0, &out)
        return out
    }
}
