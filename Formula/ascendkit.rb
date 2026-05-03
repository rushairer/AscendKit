class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.0/ascendkit-1.4.0-macos-universal.tar.gz"
  sha256 "71ddeb428b5e12bd4e681626af85e39efadce5e0e2e4faecac9b04aa3cdf67dd"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
