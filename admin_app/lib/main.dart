import 'package:flutter/material.dart';
import 'services/api.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
void main(){WidgetsFlutterBinding.ensureInitialized();runApp(const AfakdecoApp());}
class AfakdecoApp extends StatelessWidget{const AfakdecoApp({super.key});@override Widget build(BuildContext c)=>MaterialApp(title:'AFAKDECO PARK',debugShowCheckedModeBanner:false,theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF111111))),home:FutureBuilder<bool>(future:Api.instance.hasToken(),builder:(_,s)=>!s.hasData?const Scaffold(body:Center(child:CircularProgressIndicator())):s.data!?const HomeScreen():const LoginScreen()));}
