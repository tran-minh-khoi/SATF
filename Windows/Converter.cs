using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using SkiaSharp;

namespace SATF;

public static class Converter
{
    private enum Kind { Image, Pdf, Word, Excel, PowerPoint, Text, Video, Audio, Archive, Unknown }

    private static readonly Dictionary<string, Kind> Kinds = new(StringComparer.OrdinalIgnoreCase)
    {
        [".png"] = Kind.Image, [".jpg"] = Kind.Image, [".jpeg"] = Kind.Image, [".bmp"] = Kind.Image,
        [".gif"] = Kind.Image, [".tiff"] = Kind.Image, [".tif"] = Kind.Image, [".webp"] = Kind.Image,
        [".ico"] = Kind.Image, [".heic"] = Kind.Image, [".avif"] = Kind.Image,
        [".pdf"] = Kind.Pdf,
        [".doc"] = Kind.Word, [".docx"] = Kind.Word, [".odt"] = Kind.Word, [".rtf"] = Kind.Word,
        [".xls"] = Kind.Excel, [".xlsx"] = Kind.Excel, [".xlsm"] = Kind.Excel, [".ods"] = Kind.Excel, [".csv"] = Kind.Excel,
        [".ppt"] = Kind.PowerPoint, [".pptx"] = Kind.PowerPoint, [".odp"] = Kind.PowerPoint,
        [".txt"] = Kind.Text, [".md"] = Kind.Text, [".html"] = Kind.Text, [".htm"] = Kind.Text,
        [".json"] = Kind.Text, [".xml"] = Kind.Text, [".log"] = Kind.Text,
        [".mp4"] = Kind.Video, [".mov"] = Kind.Video, [".mkv"] = Kind.Video, [".avi"] = Kind.Video,
        [".mp3"] = Kind.Audio, [".wav"] = Kind.Audio, [".m4a"] = Kind.Audio, [".aac"] = Kind.Audio, [".flac"] = Kind.Audio,
        [".zip"] = Kind.Archive, [".rar"] = Kind.Archive, [".7z"] = Kind.Archive, [".tar"] = Kind.Archive, [".gz"] = Kind.Archive,
        [".tgz"] = Kind.Archive, [".bz2"] = Kind.Archive, [".tbz2"] = Kind.Archive, [".xz"] = Kind.Archive, [".txz"] = Kind.Archive,
    };

    private static Kind KindOf(string path) =>
        Directory.Exists(path) ? Kind.Unknown : Kinds.GetValueOrDefault(Path.GetExtension(path), Kind.Unknown);

    /// Xếp theo mức hay dùng: cái phổ biến đứng trước. ZIP luôn ở cuối, file nào cũng nén được.
    public static List<string> GetTargetFormats(string filePath)
    {
        if (KindOf(filePath) == Kind.Archive) return ["EXTRACT"];
        string[] list = KindOf(filePath) switch
        {
            Kind.Image => ["JPG", "PNG", "PDF", "WEBP", "GIF", "TIFF", "BMP"],
            Kind.Pdf => ["JPG", "PNG", "DOCX"],
            Kind.Word => ["PDF", "DOCX", "TXT", "RTF", "HTML", "ODT"],
            Kind.Excel => ["PDF", "XLSX", "CSV"],
            Kind.PowerPoint => ["PDF", "PNG", "JPG", "PPTX"],
            Kind.Text => ["PDF", "DOCX", "TXT", "HTML", "MD"],
            Kind.Video => ["MP4", "MP3", "M4A", "WAV"],
            Kind.Audio => ["MP3", "M4A", "WAV"],
            _ => [],
        };
        var own = Path.GetExtension(filePath).TrimStart('.').ToUpperInvariant() switch
        {
            "JPEG" => "JPG", "TIF" => "TIFF", "HTM" => "HTML", var e => e,
        };
        return list.Where(f => f != own).Append("ZIP").ToList();
    }

    /// File mới nằm cạnh file gốc; trùng tên thì thêm " (1)", " (2)"...
    private static string Destination(string src, string ext, string suffix = "")
    {
        var dir = Path.GetDirectoryName(src) ?? "";
        var name = Path.GetFileNameWithoutExtension(src) + suffix;
        var dst = Path.Combine(dir, $"{name}.{ext.ToLowerInvariant()}");
        for (int n = 1; File.Exists(dst); n++)
            dst = Path.Combine(dir, $"{name} ({n}).{ext.ToLowerInvariant()}");
        return dst;
    }

    /// Gói tải thêm cần cho lần chuyển này (null = máy đã đủ điều kiện).
    public static AddOn? RequiredAddOn(string src, string fmt)
    {
        fmt = fmt.ToUpperInvariant();
        if (fmt == "ZIP") return null;
        var kind = KindOf(src);
        switch (kind)
        {
            case Kind.Image:
            case Kind.Pdf when fmt is "PNG" or "JPG":
            case Kind.Text when fmt is "TXT" or "MD" or "HTML":
                return null;
            case Kind.Pdf or Kind.Word or Kind.Excel or Kind.PowerPoint or Kind.Text:
                string progId = kind switch { Kind.Excel => "Excel.Application", Kind.PowerPoint => "PowerPoint.Application", _ => "Word.Application" };
                return Tools.Soffice == null && Type.GetTypeFromProgID(progId) == null ? AddOn.Office : null;
            case Kind.Video or Kind.Audio:
                return Tools.FFmpeg == null ? AddOn.Media : null;
        }
        return null;
    }

    /// Phải gọi trên thread STA (WPF imaging + Office COM).
    /// `tool`: app giải nén / nén ("builtin" hoặc id trong Archivers); null = theo Cài đặt
    public static List<string> ConvertFile(string src, string fmt, string? tool = null)
    {
        fmt = fmt.ToUpperInvariant();
        if (fmt == "ZIP") return [Zip(src, tool ?? AppSettings.Current.Compressor)];
        if (fmt == "EXTRACT") return [Extract(src, tool ?? AppSettings.Current.Extractor)];

        switch (KindOf(src))
        {
            case Kind.Image:
                var img = Destination(src, fmt);
                if (fmt == "PDF") ImageToPdf(Decode(src), img); else Encode(Decode(src), img, fmt);
                return [img];

            case Kind.Pdf when fmt is "PNG" or "JPG":
                return PdfToImages(src, src, fmt);

            case Kind.Text when fmt is "TXT" or "MD" or "HTML":
                var txt = Destination(src, fmt);
                ConvertText(src, txt, fmt);
                return [txt];

            case Kind.PowerPoint when fmt is "PNG" or "JPG":
                var pdf = Destination(src, "PDF");
                Office(src, pdf, "PDF");
                try { return PdfToImages(pdf, src, fmt); }
                finally { File.Delete(pdf); }   // PDF chỉ là bước trung gian

            case Kind.Pdf or Kind.Word or Kind.Excel or Kind.PowerPoint or Kind.Text:
                var doc = Destination(src, fmt);
                Office(src, doc, fmt);
                return [doc];

            case Kind.Video or Kind.Audio:
                var media = Destination(src, fmt);
                FFmpeg(src, media);
                return [media];
        }
        throw new NotSupportedException(L("This file type can't be converted yet", "Loại file này chưa đổi được"));
    }

    // MARK: - Ảnh

    private static BitmapSource Decode(string path)
    {
        try
        {
            using var fs = File.OpenRead(path);
            return BitmapDecoder.Create(fs, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        }
        catch
        {
            // WebP/AVIF khi Windows thiếu codec
            using var bmp = SKBitmap.Decode(path) ?? throw new InvalidOperationException(L($"Couldn't read the image {Path.GetFileName(path)}", $"Không đọc được ảnh {Path.GetFileName(path)}"));
            using var data = bmp.Encode(SKEncodedImageFormat.Png, 100);
            return BitmapFrame.Create(new MemoryStream(data.ToArray()), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        }
    }

    private static void Encode(BitmapSource img, string dst, string fmt)
    {
        if (fmt == "WEBP")
        {
            using var bmp = SKBitmap.Decode(EncodeBytes(img, new PngBitmapEncoder()));
            using var data = bmp.Encode(SKEncodedImageFormat.Webp, 90);
            File.WriteAllBytes(dst, data.ToArray());
            return;
        }
        BitmapEncoder enc = fmt switch
        {
            "JPG" => new JpegBitmapEncoder { QualityLevel = 90 },
            "BMP" => new BmpBitmapEncoder(),
            "TIFF" => new TiffBitmapEncoder(),
            "GIF" => new GifBitmapEncoder(),
            "PNG" => new PngBitmapEncoder(),
            _ => throw new NotSupportedException(L($"Couldn't save as {fmt}", $"Chưa lưu được ảnh {fmt}")),
        };
        if (fmt is "JPG" or "BMP") img = OnWhite(img);   // không có nền trong suốt
        File.WriteAllBytes(dst, EncodeBytes(img, enc));
    }

    private static byte[] EncodeBytes(BitmapSource img, BitmapEncoder enc)
    {
        enc.Frames.Add(BitmapFrame.Create(img));
        using var ms = new MemoryStream();
        enc.Save(ms);
        return ms.ToArray();
    }

    private static BitmapSource OnWhite(BitmapSource img)
    {
        var rect = new Rect(0, 0, img.PixelWidth, img.PixelHeight);
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.DrawRectangle(System.Windows.Media.Brushes.White, null, rect);
            dc.DrawImage(img, rect);
        }
        var rtb = new RenderTargetBitmap(img.PixelWidth, img.PixelHeight, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(dv);
        return rtb;
    }

    /// PDF một trang chứa ảnh JPEG
    private static void ImageToPdf(BitmapSource img, string dst)
    {
        byte[] jpg = EncodeBytes(OnWhite(img), new JpegBitmapEncoder { QualityLevel = 90 });
        int w = img.PixelWidth, h = img.PixelHeight;

        using var fs = File.Create(dst);
        var offsets = new List<long>();
        void Write(string s) { var b = Encoding.ASCII.GetBytes(s); fs.Write(b, 0, b.Length); }
        void Obj(string s) { offsets.Add(fs.Position); Write(s); }

        Write("%PDF-1.4\n");
        Obj("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
        Obj("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
        Obj($"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {w} {h}] /Contents 4 0 R /Resources << /XObject << /Im0 5 0 R >> >> >>\nendobj\n");
        var content = $"q {w} 0 0 {h} 0 0 cm /Im0 Do Q";
        Obj($"4 0 obj\n<< /Length {content.Length} >>\nstream\n{content}\nendstream\nendobj\n");
        Obj($"5 0 obj\n<< /Type /XObject /Subtype /Image /Width {w} /Height {h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {jpg.Length} >>\nstream\n");
        fs.Write(jpg, 0, jpg.Length);
        Write("\nendstream\nendobj\n");

        long xref = fs.Position;
        Write("xref\n0 6\n0000000000 65535 f \n");
        foreach (var off in offsets) Write($"{off:D10} 00000 n \n");
        Write($"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n");
    }

    /// Mỗi trang PDF thành một ảnh (dùng bộ đọc PDF có sẵn của Windows 10+).
    private static List<string> PdfToImages(string pdfPath, string nameFrom, string fmt)
    {
        var file = global::Windows.Storage.StorageFile.GetFileFromPathAsync(Path.GetFullPath(pdfPath)).AsTask().GetAwaiter().GetResult();
        var doc = global::Windows.Data.Pdf.PdfDocument.LoadFromFileAsync(file).AsTask().GetAwaiter().GetResult();
        if (doc.IsPasswordProtected) throw new InvalidOperationException(L("This PDF is password-protected", "File PDF đang khoá mật khẩu"));

        var output = new List<string>();
        for (uint i = 0; i < doc.PageCount; i++)
        {
            using var page = doc.GetPage(i);
            using var ras = new global::Windows.Storage.Streams.InMemoryRandomAccessStream();
            var opts = new global::Windows.Data.Pdf.PdfPageRenderOptions
            {
                DestinationWidth = (uint)(page.Size.Width * 2),   // ~144 DPI
                BackgroundColor = global::Windows.UI.Color.FromArgb(255, 255, 255, 255),
            };
            page.RenderToStreamAsync(ras, opts).AsTask().GetAwaiter().GetResult();
            using var stream = ras.AsStreamForRead();
            var frame = BitmapDecoder.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad).Frames[0];

            var dst = Destination(nameFrom, fmt, doc.PageCount > 1 ? $"-{i + 1}" : "");
            Encode(frame, dst, fmt);
            output.Add(dst);
        }
        if (output.Count == 0) throw new InvalidOperationException(L("This PDF is empty", "File PDF trống"));
        return output;
    }

    // MARK: - Văn bản thuần

    private static void ConvertText(string src, string dst, string fmt)
    {
        var text = File.ReadAllText(src);
        if (fmt == "HTML")
            text = $"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>{Path.GetFileName(src)}</title></head><body><pre style=\"white-space: pre-wrap; font-family: sans-serif;\">{System.Net.WebUtility.HtmlEncode(text)}</pre></body></html>";
        File.WriteAllText(dst, text, Encoding.UTF8);
    }

    // MARK: - Word, Excel, PowerPoint

    /// Thử Microsoft Office (chạy ẩn) trước, không có thì LibreOffice.
    private static void Office(string src, string dst, string fmt)
    {
        var kind = KindOf(src);
        try { OfficeCom(kind, src, dst, fmt); } catch { }
        if (File.Exists(dst)) return;
        if (LibreOffice(src, dst, fmt)) return;

        var app = kind switch { Kind.Excel => "Excel", Kind.PowerPoint => "PowerPoint", _ => "Word" };
        throw new InvalidOperationException(L($"You need Microsoft {app} or the Office add-on. Right-click the SATF icon → Add-ons…", $"Cần Microsoft {app} hoặc gói Office. Bấm chuột phải icon SATF → Gói tải thêm…"));
    }

    private static void OfficeCom(Kind kind, string src, string dst, string fmt)
    {
        string progId = kind switch { Kind.Excel => "Excel.Application", Kind.PowerPoint => "PowerPoint.Application", _ => "Word.Application" };
        var type = Type.GetTypeFromProgID(progId);
        if (type == null) return;   // chưa cài Office
        dynamic app = Activator.CreateInstance(type)!;
        try
        {
            switch (kind)
            {
                case Kind.Excel:
                    app.DisplayAlerts = false;
                    dynamic wb = app.Workbooks.Open(src, 0, true);
                    try
                    {
                        if (fmt == "PDF") wb.ExportAsFixedFormat(0, dst);   // xlTypePDF
                        else wb.SaveAs(dst, fmt == "CSV" ? 62 : 51);          // xlCSVUTF8 / xlOpenXMLWorkbook
                    }
                    finally { wb.Close(false); }
                    break;

                case Kind.PowerPoint:
                    dynamic pres = app.Presentations.Open(src, -1, 0, 0);  // ReadOnly, không mở cửa sổ
                    try { pres.SaveAs(dst, fmt == "PDF" ? 32 : 24); }        // ppSaveAsPDF / ppSaveAsOpenXMLPresentation
                    finally { pres.Close(); }
                    break;

                default:   // Word: cũng mở được PDF, TXT, HTML
                    app.Visible = false;
                    app.DisplayAlerts = 0;
                    dynamic doc = app.Documents.Open(src, false, true);
                    try
                    {
                        if (fmt == "PDF") doc.ExportAsFixedFormat(dst, 17);   // wdExportFormatPDF
                        else doc.SaveAs2(dst, fmt switch
                        {
                            "TXT" => 7,    // wdFormatUnicodeText (giữ được tiếng Việt)
                            "RTF" => 6,
                            "HTML" => 10,  // wdFormatFilteredHTML
                            "ODT" => 23,
                            _ => 16,       // wdFormatDocumentDefault (docx)
                        });
                    }
                    finally { doc.Close(false); }
                    break;
            }
        }
        finally
        {
            try { app.Quit(); } catch { }
            Marshal.FinalReleaseComObject(app);
        }
    }

    private static bool LibreOffice(string src, string dst, string fmt)
    {
        var exe = Tools.Soffice;
        if (exe == null) return false;

        var tmp = Directory.CreateTempSubdirectory("satf").FullName;
        try
        {
            var ext = fmt.ToLowerInvariant();
            // Hồ sơ riêng để không đụng LibreOffice người dùng đang mở
            var profile = new Uri(Path.Combine(Path.GetTempPath(), "satf-lo-profile")).AbsoluteUri;
            Run(exe, $"\"-env:UserInstallation={profile}\" --headless --convert-to {ext} --outdir \"{tmp}\" \"{src}\"", 180_000);
            var output = Path.Combine(tmp, Path.GetFileNameWithoutExtension(src) + "." + ext);
            if (!File.Exists(output)) return false;
            File.Move(output, dst);
            return true;
        }
        finally { try { Directory.Delete(tmp, true); } catch { } }
    }

    // MARK: - Khác

    private static string Zip(string src, string tool)
    {
        var dst = Destination(src, "ZIP");
        if (Archivers.Find(tool) is ArchiveTool app)
        {
            Run(app.Exe, Archivers.CompressArgs(app, src, dst), 600_000);
            if (!File.Exists(dst)) throw new InvalidOperationException(L($"{app.Name} couldn't compress this file", $"{app.Name} chưa nén được file này"));
            return dst;
        }
        if (Directory.Exists(src))
        {
            ZipFile.CreateFromDirectory(src, dst, CompressionLevel.Optimal, includeBaseDirectory: true);
        }
        else
        {
            using var zip = ZipFile.Open(dst, ZipArchiveMode.Create);
            zip.CreateEntryFromFile(src, Path.GetFileName(src));
        }
        return dst;
    }

    /// Giải nén ra thư mục cạnh file. Bên trong chỉ có 1 thư mục/file thì đưa thẳng ra ngoài, khỏi lồng 2 lớp.
    private static string Extract(string src, string tool)
    {
        var dir = Path.GetDirectoryName(src) ?? "";
        var name = Path.GetFileNameWithoutExtension(src);
        if (name.EndsWith(".tar", StringComparison.OrdinalIgnoreCase)) name = name[..^4];   // ví dụ .tar.gz
        var outDir = UniquePath(dir, name);
        Directory.CreateDirectory(outDir);
        try
        {
            if (Archivers.Find(tool) is ArchiveTool app)
                Run(app.Exe, Archivers.ExtractArgs(app, src, outDir), 600_000);
            else if (Path.GetExtension(src).Equals(".zip", StringComparison.OrdinalIgnoreCase))
                ZipFile.ExtractToDirectory(src, outDir);
            else
                Run(Path.Combine(Environment.SystemDirectory, "tar.exe"), $"-xf \"{src}\" -C \"{outDir}\"", 600_000);   // rar, 7z, tar, gz…
        }
        catch { }

        var items = Directory.EnumerateFileSystemEntries(outDir).ToList();
        if (items.Count == 0)
        {
            try { Directory.Delete(outDir, true); } catch { }
            throw new InvalidOperationException(L("Couldn't extract this file. It may need a password or another app.",
                                                  "Chưa giải nén được. File có thể cần mật khẩu hoặc app khác."));
        }
        if (items.Count == 1)
        {
            var target = UniquePath(dir, Path.GetFileName(items[0]));
            try
            {
                if (Directory.Exists(items[0])) Directory.Move(items[0], target); else File.Move(items[0], target);
                Directory.Delete(outDir, true);
                return target;
            }
            catch { }
        }
        return outDir;
    }

    /// "Tên", "Tên (1)", "Tên (2)"... cho file/thư mục chưa tồn tại
    private static string UniquePath(string dir, string name)
    {
        var stem = Path.GetFileNameWithoutExtension(name);
        var ext = Path.GetExtension(name);
        var path = Path.Combine(dir, name);
        for (int n = 1; File.Exists(path) || Directory.Exists(path); n++)
            path = Path.Combine(dir, $"{stem} ({n}){ext}");
        return path;
    }

    private static void FFmpeg(string src, string dst)
    {
        var exe = Tools.FFmpeg ?? throw new InvalidOperationException(
            L("You need the video & music add-on. Right-click the SATF icon → Add-ons…", "Cần gói video & nhạc. Bấm chuột phải icon SATF → Gói tải thêm…"));
        Run(exe, $"-y -i \"{src}\" \"{dst}\"", 600_000);
        if (!File.Exists(dst)) throw new InvalidOperationException(L("Conversion didn't work. Please try again.", "Chuyển không thành công, thử lại nhé"));
    }

    private static void Run(string exe, string args, int timeoutMs)
    {
        using var p = Process.Start(new ProcessStartInfo(exe, args) { CreateNoWindow = true, UseShellExecute = false })!;
        if (!p.WaitForExit(timeoutMs)) { try { p.Kill(true); } catch { } }
    }
}
