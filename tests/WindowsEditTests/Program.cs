using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using SATF;

// Kiểm tra các thao tác Edit của bản Windows trên file thật (chạy trên Windows).
int failures = 0;
void Check(bool ok, string msg) { Console.WriteLine((ok ? "PASS " : "FAIL ") + msg); if (!ok) failures++; }

// Tự cập nhật: so phiên bản, đọc dữ liệu release của GitHub
Check(Updater.IsNewer("1.2.1", "1.2.0") && Updater.IsNewer("1.10.0", "1.9.9") && !Updater.IsNewer("1.2.0", "1.2.0") && !Updater.IsNewer("1.2", "1.2.0"), "update: version compare");
const string ReleaseJson = """
{"tag_name":"v1.2.1","html_url":"https://github.com/tran-minh-khoi/SATF/releases/tag/v1.2.1","draft":false,"prerelease":false,
 "assets":[{"name":"SATF-1.2.1.dmg","browser_download_url":"https://github.com/tran-minh-khoi/SATF/releases/download/v1.2.1/SATF-1.2.1.dmg","digest":"sha256:AA"},
           {"name":"SATF-Setup-1.2.1.exe","browser_download_url":"https://github.com/tran-minh-khoi/SATF/releases/download/v1.2.1/SATF-Setup-1.2.1.exe","digest":"sha256:ABCDEF"}]}
""";
Check(Updater.Parse(ReleaseJson) is { Version: "1.2.1", Sha256: "abcdef" } rel && rel.SetupUrl.EndsWith("SATF-Setup-1.2.1.exe"), "update: parse release");
Check(Updater.Parse(ReleaseJson.Replace("https://github.com/tran-minh-khoi/SATF/releases/download/v1.2.1/SATF-Setup", "https://evil.example/SATF-Setup")) == null, "update: reject foreign download link");
Check(Updater.Parse(ReleaseJson.Replace("\"prerelease\":false", "\"prerelease\":true")) == null, "update: skip pre-releases");

var dir = Directory.CreateTempSubdirectory("satf-test").FullName;
var thread = new Thread(() =>
{
    // Ảnh chụp giả 3000x2000 JPG, cờ xoay 6 (chụp dọc), có thông tin máy chụp
    var photo = Path.Combine(dir, "photo.jpg");
    var bmp = new WriteableBitmap(3000, 2000, 96, 96, PixelFormats.Bgr32, null);
    var px = new byte[3000 * 2000 * 4];
    new Random(1).NextBytes(px);   // nhiễu: ảnh nặng, nén mới thấy khác biệt
    bmp.WritePixels(new System.Windows.Int32Rect(0, 0, 3000, 2000), px, 3000 * 4, 0);
    var meta = new BitmapMetadata("jpg");
    meta.SetQuery("/app1/ifd/{ushort=274}", (ushort)6);          // Orientation
    meta.SetQuery("/app1/ifd/{ushort=272}", "TestCam 9000");     // Model
    var enc = new JpegBitmapEncoder { QualityLevel = 95 };
    enc.Frames.Add(BitmapFrame.Create(bmp, null, meta, null));
    using (var fs = File.Create(photo)) enc.Save(fs);
    var png = Path.Combine(dir, "pic.png");
    var penc = new PngBitmapEncoder(); penc.Frames.Add(BitmapFrame.Create(bmp)); using (var fs = File.Create(png)) penc.Save(fs);

    (int W, int H, bool Model) Info(string p)
    {
        using var fs = File.OpenRead(p);
        var f = BitmapDecoder.Create(fs, BitmapCreateOptions.None, BitmapCacheOption.OnLoad).Frames[0];
        bool model = (f.Metadata as BitmapMetadata)?.CameraModel is { Length: > 0 };
        return (f.PixelWidth, f.PixelHeight, model);
    }
    long Size(string p) => new FileInfo(p).Length;
    List<string> Run(string fmt, params string[] files)
    {
        try { return Converter.ConvertAll(files, fmt); }
        catch (Exception ex) { Check(false, $"{fmt} threw: {ex.Message}"); return []; }
    }
    Console.WriteLine($"source {Info(photo)} {Size(photo) / 1000}KB");

    var t = Converter.GetTargetFormats(photo);
    Check(t.Where(Converter.IsEdit).SequenceEqual([Converter.Rotate, Converter.Resize, Converter.Compress, Converter.Shrink, Converter.Clean]), "photo edits: " + string.Join(",", t.Where(Converter.IsEdit)));
    Check(!Converter.GetTargetFormats(png).Contains(Converter.Compress), "png has no Compress");
    Check(Converter.GetTargetFormats(new List<string> { photo, png }).Where(Converter.IsEdit).Take(2).SequenceEqual([Converter.MergePdf, Converter.Stack]), "multi: merge + stack first");

    if (Run(Converter.Rotate, photo) is [var r1]) { var i = Info(r1); Console.WriteLine($"rotate {i}"); Check(i.W == 3000 && i.H == 2000, "rotate applies EXIF then turns 90°"); }
    AppSettings.Current.ResizeEdge = 1920;
    if (Run(Converter.Resize, photo) is [var r2]) { var i = Info(r2); Console.WriteLine($"resize {i}"); Check(i.W == 1280 && i.H == 1920, "resize long side 1920, portrait kept"); }
    AppSettings.Current.CompressLevel = CompressLevel.Strong;
    if (Run(Converter.Compress, photo) is [var r3]) Check(Size(r3) < Size(photo), $"compress smaller ({Size(r3) / 1000}KB)");
    AppSettings.Current.TargetSizeKB = 500;
    if (Run(Converter.Shrink, photo) is [var r4]) Check(Size(r4) <= 500_000, $"shrink under 500KB ({Size(r4) / 1000}KB)");
    if (Run(Converter.Shrink, png) is [var r5]) Check(r5.EndsWith(".jpg") && Size(r5) <= 500_000, "png shrinks to jpg");
    if (Run(Converter.Clean, photo) is [var r6]) { var i = Info(r6); Check(!i.Model && i.W == 2000 && i.H == 3000, $"clean removes camera info, keeps upright {i}"); }
    if (Run(Converter.Rotate, png) is [var r7]) Check(r7.EndsWith(".png"), "png stays png");
    if (Run(Converter.Stack, photo, png) is [var r8]) { var i = Info(r8); Check(i.W == 1600, $"stack width 1600 {i}"); }

    // PDF 3 trang -> xoay
    if (Run(Converter.MergePdf, photo, png, photo) is [var pdf])
    {
        Check(Converter.GetTargetFormats(pdf).Where(Converter.IsEdit).SequenceEqual([Converter.SplitPdf, Converter.Rotate]), "pdf edits");
        if (Run(Converter.Rotate, pdf) is [var rp])
        {
            using var d = PdfSharp.Pdf.IO.PdfReader.Open(rp, PdfSharp.Pdf.IO.PdfDocumentOpenMode.Import);
            Check(d.PageCount == 3 && d.Pages[0].Rotate == 90, "pdf rotated 90, 3 pages");
        }
    }
});
thread.SetApartmentState(ApartmentState.STA);
thread.Start();
thread.Join();
Console.WriteLine(failures == 0 ? "ALL PASS" : $"{failures} FAILED");
return failures == 0 ? 0 : 1;
