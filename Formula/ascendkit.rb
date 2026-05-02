class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.14.0/ascendkit-0.14.0-macos-arm64.tar.gz"
  sha256 "a849c5886ef54131554aed62319ade6a07d3abd28876c4ef71185ea4809aa796"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
