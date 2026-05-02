class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.27.0/ascendkit-0.27.0-macos-arm64.tar.gz"
  sha256 "f400a32107b8ef85196456a0f6faf4d3d995edb16fd6922c359288e88515ae89"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
