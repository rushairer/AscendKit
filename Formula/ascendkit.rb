class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.5.1/ascendkit-1.5.1-macos-universal.tar.gz"
  sha256 "1675fabac04a3f4a8eeab9577691dd07285615fa7d206e599c98ce4a0fda34c4"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
