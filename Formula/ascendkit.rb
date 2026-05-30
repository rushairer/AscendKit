class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.7.0/ascendkit-1.7.0-macos-universal.tar.gz"
  sha256 "fa5fb77d9dd2c8be92d358c52b1a1e84a445bf008ac30edc8208802a3232b204"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
