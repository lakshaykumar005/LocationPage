import Flutter
import UIKit
import GoogleMaps // Make sure this import is included

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Provide the API key for Google Maps
    GMSServices.provideAPIKey("AIzaSyCazP9litaMcU6wy-MkHk4PN0NrY1P3o0M")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
