class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.6.0/ascendkit-1.6.0-macos-universal.tar.gz"
  sha256 "398a83158be66d6715a9d89552554198aefa46594bd9e27a9ef3e4778d1b5853"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
