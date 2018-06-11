//
//  ViewController.swift
//  directions
//
//  Created by Pablo Hernandez on 12/5/18.
//  Copyright © 2018 Pablo Hernandez. All rights reserved.
//

import UIKit
import MapKit
import CoreBluetooth

class ViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate ,CBCentralManagerDelegate, CBPeripheralDelegate {

    @IBOutlet weak var connection_state: UISwitch!
    @IBOutlet weak var transport_option: UISegmentedControl!
    @IBOutlet weak var nav_option: UISegmentedControl!
    @IBOutlet weak var map_view: MKMapView!
    @IBOutlet weak var navigation_text: UILabel!
    let locationManager = CLLocationManager()
    var points = [MKPointAnnotation]()
    var steps_nav = [MKRouteStep]()
    var step_count = 0
    
    var centralManager:CBCentralManager!
    var connectingPeripheral:CBPeripheral!
    
    var speed_char:CBCharacteristic!
    var distance_char:CBCharacteristic!
    var heading_char:CBCharacteristic!
    
    let SPEED_UUID = CBUUID(string: "2A59")
    let DISTANCE_UUID = CBUUID(string: "2A5A")
    let HEADING_UUID = CBUUID(string: "2A5B")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        checkLocationAuthorizationStatus()
        locationManager.delegate = self
        //locationManager.desiredAccuracy = kCLLocationAccuracyBest // Mejorar gps
        locationManager.allowsBackgroundLocationUpdates = true // Permitir actualizar con app desc
        locationManager.requestLocation()
        locationManager.startUpdatingLocation()
        let longGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPress(gesture:)))
        map_view.delegate = self
        map_view.addGestureRecognizer(longGesture)
        
        let centralManager = CBCentralManager(delegate: self, queue: nil)
        self.centralManager = centralManager;
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func clear_button(_ sender: Any) {
        points.removeAll()
        steps_nav.removeAll()
        step_count = 0
        map_view.removeAnnotations(map_view.annotations)
        map_view.removeOverlays(map_view.overlays)
        navigation_text.text = ""
    }
    
    @IBAction func navigate_button(_ sender: Any) {
        if nav_option.selectedSegmentIndex == 0 {
            let request = MKDirectionsRequest()
            let destination = MKPlacemark(coordinate: points[0].coordinate)
            request.source = MKMapItem.forCurrentLocation()
            request.destination = MKMapItem.init(placemark: destination)
            request.requestsAlternateRoutes = false
            switch transport_option.selectedSegmentIndex {
            case 1:
                request.transportType = MKDirectionsTransportType.automobile
                break
            default:
                request.transportType = MKDirectionsTransportType.walking
                break
            }
            let direction = MKDirections(request: request)
            direction.calculate(completionHandler: {(response,error) in
                if error != nil {
                    print("Error getting directions")
                } else {
                    self.showRoute(response!)
                }
            })
        }
        
    }
    
    func showRoute(_ response: MKDirectionsResponse) {
        for route in response.routes {
            print(response.routes.count)
            var annon = [MKAnnotation]()
            for step in route.steps {
                let newannotation = MKPointAnnotation()
                newannotation.coordinate = step.polyline.coordinate
                newannotation.title = step.instructions
                annon.append(newannotation)
                print(step.instructions)
                print(step.distance)
                steps_nav.append(step)
            }
            map_view.add(route.polyline)
            map_view.addAnnotations(annon)
        }
    }
    
    @objc func longPress(gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let tappos = gesture.location(in: map_view)
            let coordinates = map_view.convert(tappos, toCoordinateFrom: map_view)
            let newannotation = MKPointAnnotation()
            newannotation.coordinate = coordinates
            let count = points.count + 1
            newannotation.title = String(count)
            points.append(newannotation)
            map_view.addAnnotation(newannotation)
        }
    }
    
    // Comprueba si se tiene permiso para usar la posici
    func checkLocationAuthorizationStatus() {
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse {
            map_view.showsUserLocation = true
            map_view.userTrackingMode = MKUserTrackingMode.follow
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let polylinerenderer = MKPolylineRenderer(overlay: overlay)
            polylinerenderer.strokeColor = UIColor.blue
            polylinerenderer.lineWidth = 4
            return polylinerenderer
        }
        return MKPolylineRenderer()
    }
    
    // GPS
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("error:: (error)")
    }
    
    func getHeading(myPos: CLLocation, point: CLLocation)->(UInt8) {
        let x = point.coordinate.latitude-myPos.coordinate.latitude
        let y = point.coordinate.longitude-myPos.coordinate.longitude
        var angle = atan2(-y,x);
        angle = Measurement(value: angle, unit: UnitAngle.radians).converted(to: UnitAngle.degrees).value
        if (angle < 0) {
            angle += 360;
        }
        angle = angle / 360.0;
        let result: UInt8
        result = UInt8(angle*256)
        return result
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var speed_toSend: UInt8
        var distance_toSend: UInt8
        var heading_toSend: UInt8
        distance_toSend = UInt8(0)
        heading_toSend = UInt8(0)
        
        if let location = locations.first {
            speed_toSend = UInt8(location.speed / 100.0)
            if nav_option.selectedSegmentIndex == 0 {
                if steps_nav.count > 0 {
                    navigation_text.text = steps_nav[step_count].instructions
                    let next = CLLocation(latitude: steps_nav[step_count].polyline.coordinate.latitude, longitude: steps_nav[step_count].polyline.coordinate.longitude)
                    let distance = location.distance(from:next)
                    distance_toSend = UInt8(distance)
                    heading_toSend = getHeading(myPos: location, point: next)
                    if distance < 15 {
                        step_count = step_count + 1
                        if step_count > steps_nav.count {
                            step_count = step_count - 1
                        }
                    }
                }
            } else {
                if points.count > 0 {
                    let next = CLLocation(latitude: points[step_count].coordinate.latitude, longitude: points[step_count].coordinate.longitude)
                    var distance = location.distance(from: next)
                    navigation_text.text = String(step_count+1) + " " + String(distance)
                    if distance > 199 {
                        distance = 199
                    }
                    distance_toSend = UInt8(distance)
                    heading_toSend = getHeading(myPos: location, point: next)
                    if distance < 15 {
                        print("AQUI")
                        step_count = step_count + 1
                        if step_count > points.count {
                            step_count = step_count - 1
                        }
                        print(step_count)
                    }
                }
            }
            print(speed_toSend)
            print(distance_toSend)
            print(heading_toSend)
            print()
            sendInfo(speed: speed_toSend, distance: distance_toSend, heading: heading_toSend)
        }
    }
    
    // Bluetooth
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }
    
    func sendInfo(speed: UInt8, distance: UInt8, heading: UInt8) {
        var data_send = Data()
        if let speed_char = speed_char {
            data_send.append([speed], count: 1)
            connectingPeripheral.writeValue(data_send, for: speed_char, type: CBCharacteristicWriteType.withResponse)
        }
        if let distance_char = distance_char {
            data_send.removeAll()
            data_send.append([distance], count: 1)
            connectingPeripheral.writeValue(data_send, for: distance_char, type: CBCharacteristicWriteType.withResponse)
        }
        if let heading_char = heading_char {
            data_send.removeAll()
            data_send.append([heading], count: 1)
            connectingPeripheral.writeValue(data_send, for: heading_char, type: CBCharacteristicWriteType.withResponse)
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("--- centralManagerDidUpdateState")
        switch central.state{
        case .poweredOn:
            print("poweredOn")
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        case .poweredOff:
            print("--- central state is powered off")
        case .resetting:
            print("--- central state is resetting")
        case .unauthorized:
            print("--- central state is unauthorized")
        case .unknown:
            print("--- central state is unknown")
        case .unsupported:
            print("--- central state is unsupported")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("--- didDiscover peripheral")
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String{
            if localName == "ESP32 DISPLAY" {
                print("--- found \(localName)")
                print(advertisementData)
                self.centralManager.stopScan()
                connectingPeripheral = peripheral
                connectingPeripheral.delegate = self
                centralManager.connect(connectingPeripheral, options: nil)
            }
        }else{
            print("!!!--- can't unwrap advertisementData[CBAdvertisementDataLocalNameKey]")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("--- didConnectPeripheral")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        connection_state.setOn(true, animated: true)
        print("--- peripheral state is \(peripheral.state)")
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if (error) != nil{
            print("!!!--- error in didDiscoverServices: \(String(describing: error?.localizedDescription))")
        }
        else {
            print("--- Found services")
            for service in peripheral.services! as [CBService]{
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error) != nil{
            print("!!!--- error in didDiscoverCharacteristicsFor: \(String(describing: error?.localizedDescription))")
        }
        else {
            if service.uuid == CBUUID(string: "1830"){
                for characteristic in service.characteristics! as [CBCharacteristic]{
                    switch characteristic.uuid.uuidString{
                    case "2A59": // Speed
                        speed_char = characteristic
                        break;
                    case "2A5A": // Distance
                        distance_char = characteristic
                        break;
                    case "2A5B": // Heading
                        heading_char = characteristic
                        break;
                    default:
                        print("Found unespected characteristic")
                    }
                }
            }
        }
    }

}

