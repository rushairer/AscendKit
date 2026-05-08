class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.6/ascendkit-1.4.6-macos-universal.tar.gz"
  sha256 "30f4f79f0c588f9fc3e4c5e5ac9ea7e42f9126108ae1f2a6ed47b6981fe9bcc0"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
