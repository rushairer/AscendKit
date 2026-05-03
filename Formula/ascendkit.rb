class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.3.0/ascendkit-1.3.0-macos-universal.tar.gz"
  sha256 "83fed13bef19d6da2d918ed6589a3967a102c3e21891ba406556660d98f25e0f"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
