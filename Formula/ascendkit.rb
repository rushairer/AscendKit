class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.5.2/ascendkit-1.5.2-macos-universal.tar.gz"
  sha256 "a39b84b83648c00f770740a27f66f7e7823433a3eed669ae832b71db3227e697"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
