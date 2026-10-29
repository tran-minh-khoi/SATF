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
using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;
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

    /// Nhiều file -> một PDF
    public const string MergePdf = "MERGE_PDF";
    /// Một PDF -> mỗi trang một PDF
    public const string SplitPdf = "SPLIT_PDF";
    // Nhóm "Edit" (giống bản Mac): kết quả luôn là file mới bên cạnh file gốc
    public const string Rotate = "ROTATE";          // xoay 90° theo chiều kim đồng hồ (ảnh, PDF)
    public const string Resize = "RESIZE";          // thu nhỏ ảnh theo cạnh dài trong Cài đặt
    public const string Compress = "COMPRESS";      // nén ảnh JPG/WebP theo mức trong Cài đặt
    public const string Shrink = "SHRINK";          // ép ảnh xuống dưới dung lượng trong Cài đặt
    public const string Clean = "CLEAN";            // xoá EXIF, vị trí GPS
    public const string Stack = "STACK";            // nhiều ảnh -> một ảnh dài

    public static bool IsEdit(string fmt) => fmt is MergePdf or SplitPdf or Rotate or Resize or Compress or Shrink or Clean or Stack;

    /// Tên hiện trên menu
    public static string Label(string fmt) => fmt switch
    {
        "EXTRACT" => L("Extract", "Giải nén"),
        MergePdf => L("Merge PDF", "Gộp PDF"),
        SplitPdf => L("Split pages", "Tách trang"),
        Rotate => L("Rotate", "Xoay"),
        Resize => L("Resize", "Thu nhỏ"),
        Compress => L("Compress", "Nén ảnh"),
        Shrink => "< " + AppSettings.SizeLabel(AppSettings.Current.TargetSizeKB),
        Clean => L("Clean info", "Xoá EXIF"),
        Stack => L("Stack", "Ghép dọc"),
        _ => fmt,
    };

    /// Dòng mô tả dưới menu khi rê vào
    public static string Caption(string fmt, int count) => fmt switch
    {
        "EXTRACT" => L("Extract here", "Giải nén tại đây"),
        MergePdf => L($"Merge {count} files into one PDF", $"Gộp {count} file thành một PDF"),
        SplitPdf => L("One PDF per page", "Tách mỗi trang thành một PDF"),
        "ZIP" when count > 1 => L($"Compress {count} files into one ZIP", $"Nén {count} file thành một ZIP"),
        Rotate => L("Rotate 90° · saves a copy", "Xoay 90° · lưu thành bản mới"),
        Resize => L($"Resize to {AppSettings.Current.ResizeEdge}px on the long side", $"Thu nhỏ còn cạnh dài {AppSettings.Current.ResizeEdge}px"),
        Compress => L($"Make it smaller · {AppSettings.LevelLabel(AppSettings.Current.CompressLevel)}", $"Giảm dung lượng · {AppSettings.LevelLabel(AppSettings.Current.CompressLevel)}"),
        Shrink => L($"Make it under {AppSettings.SizeLabel(AppSettings.Current.TargetSizeKB)}", $"Ép xuống dưới {AppSettings.SizeLabel(AppSettings.Current.TargetSizeKB)}"),
        Clean => L("Remove location & camera info", "Xoá vị trí & thông tin máy chụp"),
        Stack => L($"Stack {count} images into one tall image", $"Ghép {count} ảnh thành một ảnh dài"),
        _ => L($"Convert to {Label(fmt)}", $"Chuyển sang {Label(fmt)}"),
    };

    /// Định dạng ảnh (đổi giữa các định dạng ảnh thì chỉ hiện tên, không cần icon)
    public static bool IsImageFormat(string fmt) => fmt is "JPG" or "PNG" or "WEBP" or "GIF" or "TIFF" or "BMP";
    public static bool IsImage(string path) => KindOf(path) == Kind.Image;

    /// Dòng thông báo khi đang làm lâu
    public static string ProgressTitle(string fmt) => fmt switch
    {
        "EXTRACT" => L("Extracting…", "Đang giải nén…"),
        "ZIP" => L("Compressing…", "Đang nén…"),
        MergePdf => L("Merging into one PDF…", "Đang gộp thành một PDF…"),
        SplitPdf => L("Splitting PDF…", "Đang tách PDF…"),
        Stack => L("Stacking images…", "Đang ghép ảnh…"),
        Rotate or Resize or Compress or Shrink or Clean => L("Working…", "Đang xử lý…"),
        _ => L($"Converting to {fmt}…", $"Đang chuyển sang {fmt}…"),
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
            Kind.Pdf => ["JPG", "PNG", "DOCX", SplitPdf, Rotate],
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
        var result = list.Where(f => f != own).ToList();
        if (KindOf(filePath) == Kind.Image && EditableExts.Contains(own))
        {
            result.AddRange([Rotate, Resize]);
            if (own is "JPG" or "WEBP") result.Add(Compress);
            result.AddRange([Shrink, Clean]);
        }
        result.Add("ZIP");
        return result;
    }

    /// Ảnh sửa được và lưu lại đúng định dạng gốc (GIF động, ICO, HEIC/AVIF thì không: Windows không ghi được)
    private static readonly HashSet<string> EditableExts = ["JPG", "PNG", "BMP", "TIFF", "WEBP"];

    /// Nhiều file:
    /// - "Gộp PDF" đứng đầu nếu file nào cũng đổi được sang PDF (PDF, Word, Excel, PowerPoint, ảnh, văn bản)
    /// - các định dạng mà file nào cũng đổi được (mỗi file ra một file mới)
    /// - ZIP luôn ở cuối: nén tất cả vào một file, kể cả khi có file nén
    public static List<string> GetTargetFormats(IReadOnlyList<string> files)
    {
        if (files.Count == 0) return [];
        if (files.Count == 1) return GetTargetFormats(files[0]);

        var common = GetTargetFormats(files[0]).Where(f => f != "ZIP").ToList();
        foreach (var f in files.Skip(1)) common = common.Intersect(GetTargetFormats(f)).ToList();

        // Gộp/ghép đứng đầu nhóm Edit vì đó là lý do hay cầm nhiều file nhất
        var result = new List<string>();
        if (files.All(f => KindOf(f) is Kind.Image or Kind.Pdf or Kind.Word or Kind.Excel or Kind.PowerPoint or Kind.Text))
            result.Add(MergePdf);
        if (files.All(f => KindOf(f) == Kind.Image)) result.Add(Stack);
        result.AddRange(common);
        result.Add("ZIP");
        return result;
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
        if (fmt is "ZIP" or SplitPdf or Rotate or Resize or Compress or Shrink or Clean or Stack) return null;
        var kind = KindOf(src);
        if (fmt == MergePdf)
        {
            if (kind is Kind.Pdf or Kind.Image) return null;   // gộp thẳng, không cần đổi
            fmt = "PDF";
        }
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

    /// Chuyển cả nhóm file đang cầm. Gộp PDF và ZIP nhiều file cho ra một file; còn lại mỗi file ra file mới riêng.
    /// Phải gọi trên thread STA (WPF imaging + Office COM).
    public static List<string> ConvertAll(IReadOnlyList<string> files, string fmt, string? tool = null)
    {
        fmt = fmt.ToUpperInvariant();
        if (fmt == MergePdf) return [MergeToPdf(files)];
        if (fmt == Stack) return [StackImages(files)];
        if (fmt == "ZIP" && files.Count > 1) return [ZipMany(files, tool ?? AppSettings.Current.Compressor)];
        var created = new List<string>();
        foreach (var f in files) created.AddRange(ConvertFile(f, fmt, tool));
        return created;
    }

    /// Phải gọi trên thread STA (WPF imaging + Office COM).
    /// `tool`: app giải nén / nén ("builtin" hoặc id trong Archivers); null = theo Cài đặt
    public static List<string> ConvertFile(string src, string fmt, string? tool = null)
    {
        fmt = fmt.ToUpperInvariant();
        if (fmt == "ZIP") return [Zip(src, tool ?? AppSettings.Current.Compressor)];
        if (fmt == "EXTRACT") return [Extract(src, tool ?? AppSettings.Current.Extractor)];
        if (fmt == MergePdf) return [MergeToPdf([src])];
        if (fmt == SplitPdf) return SplitPdfPages(src);
        if (fmt == Stack) return [StackImages([src])];
        if (fmt == Rotate && KindOf(src) == Kind.Pdf) return [RotatePdf(src)];
        if (fmt is Rotate or Resize or Compress or Shrink or Clean) return [EditImage(src, fmt)];

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

    // MARK: - Sửa ảnh (lưu lại đúng định dạng gốc)

    /// Ảnh đã xoay đúng chiều theo EXIF (ảnh chụp điện thoại hay lưu nằm ngang + cờ xoay)
    private static BitmapSource DecodeOriented(string path)
    {
        var img = Decode(path);
        int orientation = 1;
        try
        {
            using var fs = File.OpenRead(path);
            var frame = BitmapDecoder.Create(fs, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None).Frames[0];
            if ((frame.Metadata as BitmapMetadata)?.GetQuery("System.Photo.Orientation") is ushort o) orientation = o;
        }
        catch { }
        Transform? t = orientation switch
        {
            2 => new ScaleTransform(-1, 1), 3 => new RotateTransform(180), 4 => new ScaleTransform(1, -1),
            5 => new TransformGroup { Children = { new ScaleTransform(-1, 1), new RotateTransform(270) } },
            6 => new RotateTransform(90),
            7 => new TransformGroup { Children = { new ScaleTransform(-1, 1), new RotateTransform(90) } },
            8 => new RotateTransform(270),
            _ => null,
        };
        if (t == null) return img;
        var turned = new TransformedBitmap(img, t);
        turned.Freeze();
        return turned;
    }

    private static string ExtOf(string path) => Path.GetExtension(path).TrimStart('.').ToUpperInvariant() switch
    {
        "JPEG" => "JPG", "TIF" => "TIFF", var e => e,
    };

    /// Mã hoá ảnh với chất lượng tuỳ chọn (JPG/WebP); định dạng khác không mất dữ liệu
    private static byte[] EncodeImage(BitmapSource img, string fmt, int quality)
    {
        if (fmt == "WEBP")
        {
            using var bmp = SKBitmap.Decode(EncodeBytes(img, new PngBitmapEncoder()));
            using var data = bmp.Encode(SKEncodedImageFormat.Webp, quality);
            return data.ToArray();
        }
        BitmapEncoder enc = fmt switch
        {
            "JPG" => new JpegBitmapEncoder { QualityLevel = quality },
            "BMP" => new BmpBitmapEncoder(),
            "TIFF" => new TiffBitmapEncoder(),
            "PNG" => new PngBitmapEncoder(),
            _ => throw new NotSupportedException(L($"Couldn't save as {fmt}", $"Chưa lưu được ảnh {fmt}")),
        };
        if (fmt is "JPG" or "BMP") img = OnWhite(img);
        return EncodeBytes(img, enc);
    }

    private static string EditImage(string src, string op)
    {
        var ext = ExtOf(src);
        if (!EditableExts.Contains(ext)) throw new NotSupportedException(L("This image type can't be edited", "Loại ảnh này chưa sửa được"));
        string Save(BitmapSource img, string suffix, int quality = 90)
        {
            var dst = Destination(src, ext, suffix);
            File.WriteAllBytes(dst, EncodeImage(img, ext, quality));
            return dst;
        }

        switch (op)
        {
            case Rotate:
                var turned = new TransformedBitmap(DecodeOriented(src), new RotateTransform(90));
                return Save(turned, L(" (rotated)", " (xoay)"));

            case Resize:
            {
                int edge = AppSettings.Current.ResizeEdge;
                var img = DecodeOriented(src);
                int longSide = Math.Max(img.PixelWidth, img.PixelHeight);
                if (longSide <= edge) throw new InvalidOperationException(L($"This image is already {edge}px or smaller", $"Ảnh này đã nhỏ hơn {edge}px"));
                double k = (double)edge / longSide;
                return Save(new TransformedBitmap(img, new ScaleTransform(k, k)), $" ({edge}px)");
            }

            case Compress:
            {
                var dst = Save(DecodeOriented(src), L(" (compressed)", " (nén)"), AppSettings.Quality(AppSettings.Current.CompressLevel));
                // Ảnh đã nén sẵn: kết quả không nhỏ hơn thì bỏ, khỏi để lại file thừa
                if (new FileInfo(dst).Length >= new FileInfo(src).Length)
                {
                    File.Delete(dst);
                    throw new InvalidOperationException(L("This image is already well compressed", "Ảnh này đã được nén tốt rồi"));
                }
                return dst;
            }

            case Shrink:
                return ShrinkImage(src);

            case Clean:
                // Mã hoá lại không kèm metadata (WPF không chép metadata sang file mới). Hướng xoay được áp thẳng vào ảnh.
                return Save(DecodeOriented(src), L(" (clean)", " (sạch)"), 95);
        }
        throw new NotSupportedException(op);
    }

    /// Hạ chất lượng (và nếu cần thì thu nhỏ) tới khi file dưới dung lượng trong Cài đặt. PNG/BMP/TIFF lưu thành JPG.
    private static string ShrinkImage(string src)
    {
        int limitKB = AppSettings.Current.TargetSizeKB;
        long limit = limitKB * 1000L;
        var label = AppSettings.SizeLabel(limitKB);
        if (new FileInfo(src).Length <= limit) throw new InvalidOperationException(L($"This image is already under {label}", $"Ảnh này đã dưới {label} rồi"));

        var ext = ExtOf(src) is "JPG" or "WEBP" ? ExtOf(src) : "JPG";
        BitmapSource full = DecodeOriented(src), img = full;
        while (true)
        {
            // Tìm chất lượng cao nhất còn vừa dung lượng (chia đôi 6 lần, đủ mịn)
            int low = 30, high = 92;
            byte[]? best = null;
            var first = EncodeImage(img, ext, low);
            if (first.Length <= limit)
            {
                best = first;
                for (int i = 0; i < 6; i++)
                {
                    int mid = (low + high) / 2;
                    var d = EncodeImage(img, ext, mid);
                    if (d.Length <= limit) { best = d; low = mid; } else high = mid;
                }
            }
            if (best != null)
            {
                var dst = Destination(src, ext, L($" (under {label})", $" (dưới {label})"));
                File.WriteAllBytes(dst, best);
                return dst;
            }
            // Chất lượng thấp nhất vẫn quá nặng -> thu nhỏ 20% rồi thử lại
            double k = img.PixelWidth * 0.8 / full.PixelWidth;
            if (Math.Max(full.PixelWidth, full.PixelHeight) * k < 320)
                throw new InvalidOperationException(L($"Couldn't get this image under {label}", $"Không ép được ảnh này xuống dưới {label}"));
            var smaller = new TransformedBitmap(full, new ScaleTransform(k, k));
            smaller.Freeze();
            img = smaller;
        }
    }

    /// Nhiều ảnh -> một ảnh dài, xếp từ trên xuống theo thứ tự đang cầm, cùng chiều rộng.
    private static string StackImages(IReadOnlyList<string> files)
    {
        var images = files.Select(DecodeOriented).ToList();
        // ponytail: giới hạn kích thước cố định để không ngốn RAM; muốn ảnh lớn hơn thì cho chọn trong Cài đặt
        int width = Math.Min(images.Max(i => i.PixelWidth), 1600);
        int Height(int w) => images.Sum(i => (int)Math.Round(i.PixelHeight * (double)w / i.PixelWidth));
        while (Height(width) > 30_000 && width > 400) width = width * 3 / 4;
        int total = Height(width);

        var dv = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality);
        using (var dc = dv.RenderOpen())
        {
            double top = 0;
            foreach (var img in images)
            {
                double h = Math.Round(img.PixelHeight * (double)width / img.PixelWidth);
                dc.DrawImage(img, new Rect(0, top, width, h));
                top += h;
            }
        }
        var rtb = new RenderTargetBitmap(width, total, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(dv);

        bool allPng = files.All(f => ExtOf(f) == "PNG");
        var dst = Destination(files[0], allPng ? "PNG" : "JPG", L(" (stacked)", " (ghép)"));
        File.WriteAllBytes(dst, EncodeImage(rtb, allPng ? "PNG" : "JPG", 90));
        return dst;
    }

    /// Xoay mọi trang 90° theo chiều kim đồng hồ
    private static string RotatePdf(string src)
    {
        PdfDocument doc;
        try { doc = PdfReader.Open(src, PdfDocumentOpenMode.Modify); }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            throw new InvalidOperationException(L($"Couldn't open {Path.GetFileName(src)}. It may be password-protected or damaged.",
                                                  $"Không mở được {Path.GetFileName(src)}, có thể file đang khoá mật khẩu hoặc bị hỏng."), ex);
        }
        using (doc)
        {
            foreach (var page in doc.Pages) page.Rotate = (page.Rotate + 90) % 360;
            var dst = Destination(src, "PDF", L(" (rotated)", " (xoay)"));
            doc.Save(dst);
            return dst;
        }
    }

    // MARK: - Gộp / tách PDF

    /// Gộp nhiều file thành một PDF, theo đúng thứ tự đang cầm. File không phải PDF được đổi sang PDF trước
    /// (ảnh: mỗi ảnh một trang; Word, Excel, PowerPoint, văn bản: như khi đổi sang PDF).
    private static string MergeToPdf(IReadOnlyList<string> files)
    {
        var tmp = Directory.CreateTempSubdirectory("satf").FullName;
        try
        {
            using var merged = new PdfDocument();
            for (int i = 0; i < files.Count; i++)
            {
                var src = files[i];
                var pdf = Path.Combine(tmp, $"{i}.pdf");
                switch (KindOf(src))
                {
                    case Kind.Pdf: pdf = src; break;
                    case Kind.Image: ImageToPdf(Decode(src), pdf); break;
                    case Kind.Word or Kind.Excel or Kind.PowerPoint or Kind.Text: Office(src, pdf, "PDF"); break;
                    default: throw new NotSupportedException(L($"{Path.GetFileName(src)} can't be added to a PDF", $"Không gộp được {Path.GetFileName(src)} vào PDF"));
                }
                using var input = OpenPdf(pdf, Path.GetFileName(src));
                foreach (var page in input.Pages) merged.AddPage(page);
            }
            if (merged.PageCount == 0) throw new InvalidOperationException(L("Nothing to merge", "Không có trang nào để gộp"));
            var dst = Destination(files[0], "PDF", L(" (merged)", " (gộp)"));
            merged.Save(dst);
            return dst;
        }
        finally { try { Directory.Delete(tmp, true); } catch { } }
    }

    /// Mỗi trang thành một file PDF riêng: ten-1.pdf, ten-2.pdf...
    private static List<string> SplitPdfPages(string src)
    {
        using var input = OpenPdf(src, Path.GetFileName(src));
        if (input.PageCount < 2) throw new InvalidOperationException(L("This PDF has only one page", "File PDF này chỉ có một trang"));
        var output = new List<string>();
        for (int i = 0; i < input.PageCount; i++)
        {
            using var single = new PdfDocument();
            single.AddPage(input.Pages[i]);
            var dst = Destination(src, "PDF", $"-{i + 1}");
            single.Save(dst);
            output.Add(dst);
        }
        return output;
    }

    private static PdfDocument OpenPdf(string path, string name)
    {
        try { return PdfReader.Open(path, PdfDocumentOpenMode.Import); }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            throw new InvalidOperationException(L($"Couldn't open {name}. It may be password-protected or damaged.",
                                                  $"Không mở được {name}, có thể file đang khoá mật khẩu hoặc bị hỏng."), ex);
        }
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
            Run(app.Exe, Archivers.CompressArgs(app, [src], dst), 600_000);
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

    /// Nén nhiều file / thư mục vào một file "Archive.zip" cạnh file đầu tiên.
    private static string ZipMany(IReadOnlyList<string> files, string tool)
    {
        var dst = UniquePath(Path.GetDirectoryName(files[0]) ?? "", L("Archive", "Lưu trữ") + ".zip");
        if (Archivers.Find(tool) is ArchiveTool app)
        {
            Run(app.Exe, Archivers.CompressArgs(app, files, dst), 600_000);
            if (!File.Exists(dst)) throw new InvalidOperationException(L($"{app.Name} couldn't compress these files", $"{app.Name} chưa nén được các file này"));
            return dst;
        }
        try
        {
            using var zip = ZipFile.Open(dst, ZipArchiveMode.Create);
            var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var src in files)
            {
                // Hai file trùng tên (từ hai thư mục khác nhau): thêm " (1)"
                var name = Path.GetFileName(src);
                var stem = Path.GetFileNameWithoutExtension(name);
                var ext = Path.GetExtension(name);
                for (int n = 1; !used.Add(name); n++) name = $"{stem} ({n}){ext}";

                if (Directory.Exists(src))
                {
                    foreach (var file in Directory.EnumerateFiles(src, "*", SearchOption.AllDirectories))
                        zip.CreateEntryFromFile(file, name + "/" + Path.GetRelativePath(src, file).Replace('\\', '/'), CompressionLevel.Optimal);
                }
                else
                {
                    zip.CreateEntryFromFile(src, name, CompressionLevel.Optimal);
                }
            }
        }
        catch
        {
            try { File.Delete(dst); } catch { }   // không để lại file nén dở
            throw;
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
