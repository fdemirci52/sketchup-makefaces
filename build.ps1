# SketchUp eklenti paketini (.rbz) oluşturur.
#
#   powershell -ExecutionPolicy Bypass -File build.ps1
#
# Sürüm numarası src/mf_make_faces.rb içindeki PLUGIN_VERSION'dan okunur,
# çıktı dist/MakeFaces-<sürüm>.rbz olur. Zip içindeki yollar ileri eğik çizgi
# ile yazılır; Compress-Archive ters eğik çizgi kullandığı için SketchUp'ın
# Extension Manager'ı onu düzgün açamayabiliyor.

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$src  = Join-Path $root 'src'
$dist = Join-Path $root 'dist'

$loader = Get-Content (Join-Path $src 'mf_make_faces.rb') -Raw -Encoding UTF8
if ($loader -notmatch "PLUGIN_VERSION\s*=\s*'([^']+)'") {
  throw 'PLUGIN_VERSION bulunamadi: src/mf_make_faces.rb'
}
$version = $Matches[1]

New-Item -ItemType Directory -Force $dist | Out-Null
$rbz = Join-Path $dist "MakeFaces-$version.rbz"

$files = Get-ChildItem $src -Recurse -File | Sort-Object FullName

$stream  = [System.IO.File]::Open($rbz, [System.IO.FileMode]::Create)
$archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($src.Length + 1).Replace([char]92, [char]47)
    $entry = $archive.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
    $out = $entry.Open()
    try {
      $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
      $out.Write($bytes, 0, $bytes.Length)
    } finally {
      $out.Dispose()
    }
  }
} finally {
  $archive.Dispose()
  $stream.Dispose()
}

Write-Host "Olusturuldu: dist/MakeFaces-$version.rbz ($($files.Count) dosya, $((Get-Item $rbz).Length) bayt)"
