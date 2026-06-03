class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.8.0/ascendkit-1.8.0-macos-universal.tar.gz"
  sha256 "7efc63239c92d7927a358295888eeb42164d6ba179a9745c55e6d1dee7bf9e45"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
