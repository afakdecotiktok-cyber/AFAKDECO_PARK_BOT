import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/status_icons.dart';
import 'problems_screen.dart';
import 'drivers_screen.dart';
import 'vehicle_history_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
class HomeScreen extends StatefulWidget{const HomeScreen({super.key});@override State<HomeScreen> createState()=>_HomeScreenState();}
class _HomeScreenState extends State<HomeScreen>{int tab=0;bool loading=true;String? error;List<dynamic> vehicles=[];
@override void initState(){super.initState();load();}
Future<void> load()async{setState(()=>loading=true);try{vehicles=await Api.instance.dashboard();error=null;}catch(e){error=e.toString();}if(mounted)setState(()=>loading=false);}
Future<void> logout()async{await Api.instance.logout();if(mounted)Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const LoginScreen()),(_)=>false);}
@override Widget build(BuildContext c){final pages=[_Dash(vehicles:vehicles,loading:loading,error:error,reload:load,onVehicle:(v)=>Navigator.push(c,MaterialPageRoute(builder:(_)=>VehicleHistoryScreen(vehicle:v)))),const ProblemsScreen(),const DriversScreen(),SettingsScreen(onLogout:logout)];return Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('AFAKDECO PARK'),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),body:pages[tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'الرئيسية'),NavigationDestination(icon:Icon(Icons.report_problem_outlined),label:'الشكاوى'),NavigationDestination(icon:Icon(Icons.people_outline),label:'السائقون'),NavigationDestination(icon:Icon(Icons.settings_outlined),label:'الإعدادات')])));}}
class _Dash extends StatelessWidget{final List<dynamic> vehicles;final bool loading;final String? error;final Future<void> Function() reload;final void Function(String) onVehicle;const _Dash({required this.vehicles,required this.loading,required this.error,required this.reload,required this.onVehicle});
@override Widget build(BuildContext c){if(loading)return const Center(child:CircularProgressIndicator());if(error!=null)return Center(child:Text(error!));return RefreshIndicator(onRefresh:reload,child:ListView(padding:const EdgeInsets.all(12),children:[const Text('كل المركبات',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:10),...vehicles.map((x){final v=Map<String,dynamic>.from(x);final ds=List<dynamic>.from(v['drivers']??[]);return Card(margin:const EdgeInsets.only(bottom:6),child:ListTile(leading:const Icon(Icons.directions_car_outlined),title:Text(v['vehicle'].toString()),subtitle:Text(ds.isEmpty?'بدون سائق حالي':ds.map((d)=>(d as Map)['name']).join(' • ')),trailing:StatusIcons(icons:v['status_icons']??['normal']),onTap:()=>onVehicle(v['vehicle'].toString())));})]));}}
