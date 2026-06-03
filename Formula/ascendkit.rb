class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.8.0/ascendkit-1.8.0-macos-universal.tar.gz"
  sha256 "a4587b20d928cd62d27a1233823baf3fc698fd87f92d1a587959089ccedb7f6b"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
