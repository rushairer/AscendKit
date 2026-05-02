class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.22.0/ascendkit-0.22.0-macos-arm64.tar.gz"
  sha256 "0d1c82646d17e526aa363fa4356c4467f1d19edd832eeff0f0d1f2fd80f0a769"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
