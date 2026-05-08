class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.3/ascendkit-1.4.3-macos-universal.tar.gz"
  sha256 "476551215dc34b9742b96265d5ecad0905c61fce82e6e6198b08214893d3000e"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
