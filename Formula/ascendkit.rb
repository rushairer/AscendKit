class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.1.0/ascendkit-1.1.0-macos-universal.tar.gz"
  sha256 "9c8442450f28db2e147c1c4f2e9109f800248af735a42992eb3e660909020259"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
