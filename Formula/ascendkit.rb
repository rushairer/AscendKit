class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.2/ascendkit-1.4.2-macos-universal.tar.gz"
  sha256 "df12ad7df707415b8882b077e746c31f20e8ba5ba354db5e31665e6577ff54c0"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
