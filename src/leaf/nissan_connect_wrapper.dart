import 'package:dartnissanconnect/dartnissanconnect.dart';
import 'package:dartnissanconnect/src/nissanconnect_hvac.dart';

import 'package:logging/logging.dart';

import 'builder/leaf_battery_builder.dart';
import 'builder/leaf_climate_builder.dart';
import 'builder/leaf_location_builder.dart';
import 'builder/leaf_stats_builder.dart';
import 'leaf_session.dart';
import 'leaf_vehicle.dart';

final Logger _log = Logger('NissanConnectVehicleWrapper');
const int _maxRetryCount = 5;
const int _waitBetweenRequest = 5;

class NissanConnectSessionWrapper extends LeafSessionInternal {
  NissanConnectSessionWrapper(String username, String password)
    : super(username, password);

  NissanConnectSession _session;

  @override
  Future<void> login() async {
    _session = NissanConnectSession();
    await _session.login(username: username, password: password);

    final List<VehicleInternal> newVvehicles = _session.vehicles.map((NissanConnectVehicle vehicle) =>
      NissanConnectVehicleWrapper(vehicle)).toList();

    setVehicles(newVvehicles);
  }
}

class NissanConnectVehicleWrapper extends VehicleInternal {
  NissanConnectVehicleWrapper(NissanConnectVehicle vehicle) :
    _session = vehicle.session,
    super(vehicle.nickname.toString(), vehicle.vin.toString());

  final NissanConnectSession _session;

  NissanConnectVehicle _getVehicle() =>
    _session.vehicles.firstWhere((NissanConnectVehicle v) => v.vin.toString() == vin,
      orElse: () => throw Exception('Could not find matching vehicle: $vin number of vehicles: ${_session.vehicles.length}'));

  @override
  bool isFirstVehicle() => _session.vehicle.vin == vin;

  @override
  Future<Map<String, String>> fetchDailyStatistics(DateTime targetDate) async =>
    fetchStatistics(TimeRange.Daily, await _getVehicle().requestDailyStatistics());

  @override
  Future<Map<String, String>> fetchMonthlyStatistics(DateTime targetDate) async =>
    fetchStatistics(TimeRange.Monthly, await _getVehicle().requestMonthlyStatistics(month: targetDate));

  Map<String, String> fetchStatistics(TimeRange targetTimeRange, NissanConnectStats stats) =>
    saveAndPrependVin(StatsInfoBuilder(targetTimeRange)
      .withTargetDate(stats.date)
      .withtravelTime(stats.travelTime)
      .withTravelDistanceMiles(stats.travelDistanceMiles)
      .withTravelDistanceKilometers(stats.travelDistanceKilometers)
      .withMilesPerKwh(stats.milesPerKWh)
      .withKilometersPerKwh(stats.kilometersPerKWh)
      .withKwhUsed(stats.kWhUsed)
      .withKwhPerMiles(stats.kWhPerMiles)
      .withKwhPerKilometers(stats.kWhPerKilometers)
      .withTripsNumber(stats.tripsNumber)
      .withKwhGained(stats.kWhGained)
      .build());

  @override
  Future<Map<String, String>> fetchBatteryStatusFromCar() async {
    return await _fetchBatteryStatus(true);
  }

  @override
  Future<Map<String, String>> fetchBatteryStatus() async {
    return await _fetchBatteryStatus(false);
  }

  Future<Map<String, String>> _fetchBatteryStatus(bool requestFromCar) async {
    final NissanConnectVehicle vehicle = _getVehicle();
    final DateTime startDate = requestFromCar ? DateTime.now() : DateTime.fromMicrosecondsSinceEpoch(0);
    int retryCount = _maxRetryCount;
    if(requestFromCar){
      await vehicle.requestBatteryStatusRefresh();
      await Future<void>.delayed(Duration(seconds: _waitBetweenRequest));
    }   
    NissanConnectBattery battery;
    do{
      battery = await vehicle.requestBatteryStatus();
      if(startDate.isBefore(battery.dateTime)){
        break;
      }
      await Future<void>.delayed(Duration(seconds: _waitBetweenRequest));
      retryCount--;
    }while(retryCount > 0);    
    
    final double percentage =
      double.tryParse(battery.batteryPercentage.replaceFirst('%', ''));

    _log.finer('Receveived batteryPercentage: $percentage');

    return saveAndPrependVin(BatteryInfoBuilder()
           .withChargePercentage(percentage?.round() ?? -1)
           .withConnectedStatus(battery.isConnected)
           .withChargingStatus(battery.isCharging)
           .withCruisingRangeAcOffKm(battery.cruisingRangeAcOffKm)
           .withCruisingRangeAcOffMiles(battery.cruisingRangeAcOffMiles)
           .withCruisingRangeAcOnKm(battery.cruisingRangeAcOnKm)
           .withCruisingRangeAcOnMiles(battery.cruisingRangeAcOnMiles)
           .withLastUpdatedDateTime(battery.dateTime)
           .withTimeToFullL2(battery.timeToFullNormal)
           .withTimeToFullL2_6kw(battery.timeToFullFast)
           .withTimeToFullTrickle(battery.timeToFullSlow)
           .withChargingSpeed(battery.chargingSpeed.toString())
           .build());
  }

  @override
  Future<bool> startCharging() =>
    _getVehicle().requestChargingStart();

    @override
  Future<bool> stopCharging() =>
    _getVehicle().requestChargingStop();
  
  @override
  Future<Map<String, String>> fetchClimateStatusFromCar() async {
    return await _fetchClimateStatus(true);
  }

  @override
  Future<Map<String, String>> fetchClimateStatus() async {
    return await _fetchClimateStatus(false);
  }

  Future<Map<String, String>> _fetchClimateStatus(bool requestFromCar) async {
    final NissanConnectVehicle vehicle = _getVehicle();
    final DateTime startDate = requestFromCar ? DateTime.now() : DateTime.fromMicrosecondsSinceEpoch(0);
    int retryCount = _maxRetryCount;
    if(requestFromCar){
      await vehicle.requestClimateControlStatusRefresh();
      await Future<void>.delayed(Duration(seconds: _waitBetweenRequest));
    }   
    NissanConnectHVAC hvac;
    do{
      hvac = await vehicle.requestClimateControlStatus();
      if(startDate.isBefore(hvac.dateTime)){
        break;
      }
      await Future<void>.delayed(Duration(seconds: _waitBetweenRequest));
      retryCount--;
    } while(retryCount > 0);

    return saveAndPrependVin(ClimateInfoBuilder()
            .withCabinTemperatureCelsius(hvac.cabinTemperature)
            .withHvacRunningStatus(hvac.isRunning)
            .withLastUpdatedDateTime(hvac.dateTime)
            .build());
  }

  @override
  Future<bool> startClimate(int targetTemperatureCelsius) =>
    _getVehicle().requestClimateControlOn(
      DateTime.now(),
      targetTemperatureCelsius);

  @override
  Future<bool> stopClimate() =>
    _getVehicle().requestClimateControlOff();

  @override
  Future<Map<String, String>> fetchLocation() async {
    return await _fetchLocation(false);
  }  

  @override
  Future<Map<String, String>> fetchLocationFromCar() async{
    return await _fetchLocation(true);
  }

  Future<Map<String, String>> _fetchLocation(bool requestFromCar) async {
    final NissanConnectVehicle vehicle = _getVehicle();
    final DateTime startDate = requestFromCar ? DateTime.now() : DateTime.fromMicrosecondsSinceEpoch(0);
    int retryCount = _maxRetryCount;
    if(requestFromCar){
      await vehicle.requestLocationRefresh();
      await Future<void>.delayed(Duration(seconds: _waitBetweenRequest));
    }   
    NissanConnectLocation location;
    do{
      location = await vehicle.requestLocation();
      if(startDate.isBefore(location.dateTime)){
        break;
      }
      await Future<void>.delayed(Duration(seconds: _waitBetweenRequest));
      retryCount--;
    } while(retryCount > 0);   

    return saveAndPrependVin(LocationInfoBuilder()
      .withLatitude(location.latitude)
      .withLongitude(location.longitude)
      .withLastUpdatedDateTime(location.dateTime)
      .build());
  }
}
