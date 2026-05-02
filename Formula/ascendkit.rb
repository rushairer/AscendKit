class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.0.0/ascendkit-1.0.0-macos-arm64.tar.gz"
  sha256 "b03b10ce908b538ed30b0748ccd4bbd4841a9bdd0d4f4bbd886f805ba806fe9f"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
