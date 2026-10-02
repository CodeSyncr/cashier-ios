Pod::Spec.new do |s|
  s.name         = "NimbusCashier"
  s.version      = "1.1.0"
  s.summary      = "In-app purchases through StoreKit 2, verified by Nimbus Cashier, gated on entitlements."
  s.description  = <<-DESC
    Nimbus Cashier for Apple platforms: StoreKit 2 purchases verified and tracked by your
    Cashier app, entitlements, offerings, and paywalls designed in the Cashier console drawn
    natively in SwiftUI.
  DESC
  s.homepage     = "https://github.com/CodeSyncr/cashier-ios"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = "CodeSyncr"
  s.source       = { :git => "https://github.com/CodeSyncr/cashier-ios.git", :tag => s.version.to_s }

  s.ios.deployment_target = "15.0"
  s.osx.deployment_target = "12.0"
  s.swift_versions = ["5.10"]

  s.source_files = "Sources/NimbusCashier/**/*.swift"
  # Package.swift copies Resources/paywall-art.json into the target's bundle;
  # PaywallArt.resources finds this bundle when SwiftPM's Bundle.module is absent.
  s.resource_bundles = { "NimbusCashier" => ["Sources/NimbusCashier/Resources/paywall-art.json"] }
  s.frameworks = "StoreKit", "SwiftUI"
end
