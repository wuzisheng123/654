import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

const double tireCircum = 1.42;
const int polePairs = 16;
const double speedRatio = tireCircum / polePairs * 3.6;

final List<int> antRequestFrame = [0x5A,0x5A,0x01,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
final List<int> farRequestFrame = [0xAA,0x55,0x03,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BleModel(),
      child: MaterialApp(
        title: 'LBMC风 远驱蚂蚁仪表21串',
        theme: ThemeData.dark(),
        home: const DashBoardPage(),
      ),
    );
  }
}

class BleModel extends ChangeNotifier {
  FlutterBluePlus flutterBlue = FlutterBluePlus.instance;
  BluetoothDevice? antDev;
  BluetoothDevice? farDev;
  BluetoothCharacteristic? antChar;
  BluetoothCharacteristic? farChar;

  double speed = 0.0;
  int rpm = 0;
  double busVolt = 0.0;
  double busCurrent = 0.0;
  double phaseCurrent = 0.0;
  double power = 0.0;
  double ctrlTemp = 0.0;
  double batTotalV = 0.0;
  double batCurrent = 0.0;
  double batPower = 0.0;
  int soc = 0;
  double batTemp = 0.0;
  double diffV = 0.0;
  double remainAh = 0.0;
  double soh = 100.0;
  double gpsAcc = 99;
  double tripKm = 0.0;
  String fault = "状态良好";
  List<double> cellV = List.filled(21, 0);

  bool antOnline = false;
  bool farOnline = false;

  Future<void> scanAndConnect() async {
    flutterBlue.startScan(timeout: const Duration(seconds: 4));
    flutterBlue.scanResults.listen((resList) {
      for (var r in resList) {
        String name = r.device.name;
        if (name.contains("ANT") && antDev == null) {
          antDev = r.device;
          connectAnt();
        }
        if (name.toLowerCase().contains("far") && farDev == null) {
          farDev = r.device;
          connectFar();
        }
      }
    });
  }

  Future<void> connectAnt() async {
    if (antDev == null) return;
    await antDev!.connect();
    antOnline = true;
    notifyListeners();
    List<BluetoothService> svc = await antDev!.discoverServices();
    for (var s in svc) {
      for (var c in s.characteristics) {
        if (c.properties.write && c.properties.read) {
          antChar = c;
          startAntPoll();
          break;
        }
      }
    }
  }

  Future<void> connectFar() async {
    if (farDev == null) return;
    await farDev!.connect();
    farOnline = true;
    notifyListeners();
    List<BluetoothService> svc = await farDev!.discoverServices();
    for (var s in svc) {
      for (var c in s.characteristics) {
        if (c.properties.write && c.properties.read) {
          farChar = c;
          startFarPoll();
          break;
        }
      }
    }
  }

  Future<void> startAntPoll() async {
    while (antOnline && antChar != null) {
      try {
        await antChar!.write(antRequestFrame);
        List<int> data = await antChar!.read();
        if (data.length >= 60) {
          batTotalV = (data[4] << 8 | data[5]) / 10.0;
          int rawI = (data[6] << 8 | data[7]);
          if(rawI > 32767) rawI -= 65536;
          batCurrent = rawI / 10.0;
          soc = data[10];
          batTemp = (data[12] << 8 | data[13]) / 10.0;
          List<double> cells = [];
          for(int i=0;i<21;i++){
            int pos = 16 + i*2;
            int cv = (data[pos] << 8 | data[pos+1]);
            cells.add(cv / 1000.0);
          }
          cellV = cells;
          double maxC = cells.reduce((a,b)=>a>b?a:b);
          double minC = cells.reduce((a,b)=>a<b?a:b);
          diffV = (maxC - minC)*1000;
          batPower = batTotalV * batCurrent;
        }
        notifyListeners();
      } catch (_) {
        antOnline = false;
      }
      await Future.delayed(const Duration(milliseconds:300));
    }
  }

  Future<void> startFarPoll() async {
    while (farOnline && farChar != null) {
      try {
        await farChar!.write(farRequestFrame);
        List<int> data = await farChar!.read();
        if (data.length >=10) {
          rpm = data[4] << 8 | data[5];
          busVolt = (data[6] <<8 | data[7]) /10.0;
          int rawI = (data[8]<<8|data[9]);
          if(rawI>32767) rawI -=65536;
          busCurrent = rawI /10.0;
          speed = rpm * speedRatio;
          ctrlTemp = 28.0;
          power = busVolt * busCurrent;
        }
        notifyListeners();
      } catch (_) {
        farOnline = false;
      }
      await Future.delayed(const Duration(milliseconds:200));
    }
  }

  void disconnectAll() async {
    if(antDev != null) await antDev!.disconnect();
    if(farDev != null) await farDev!.disconnect();
    antOnline = false;
    farOnline = false;
    notifyListeners();
  }
}

class DashBoardPage extends StatefulWidget {
  const DashBoardPage({super.key}
