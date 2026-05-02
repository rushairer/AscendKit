class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.1.0/ascendkit-1.1.0-macos-universal.tar.gz"
  sha256 "fd89838b581407d015e84ded74b71a5cd90a742936c95943edcf744964525b36"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
