class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.31.0/ascendkit-0.31.0-macos-arm64.tar.gz"
  sha256 "537a108621b906d343ccd4905de437e4567cd4001c319a74edbe610e8aa58155"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
