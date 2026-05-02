class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.24.0/ascendkit-0.24.0-macos-arm64.tar.gz"
  sha256 "d1b196170995a899f521ef43c95b82d7e5db8a4ef856b419c4ab386b5686903f"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
