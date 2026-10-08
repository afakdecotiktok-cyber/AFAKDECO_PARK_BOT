import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
class Api {
  Api._(); static final instance=Api._(); static const baseUrl='https://afakdeco-park-bot.onrender.com';
  Future<SharedPreferences> get _p async=>SharedPreferences.getInstance();
  Future<bool> hasToken() async=>(await _p).getString('jwt')?.isNotEmpty==true;
  Future<void> saveAuth(Map<String,dynamic> d) async{final p=await _p;await p.setString('jwt',d['token'].toString());await p.setString('role','${d['role']??''}');await p.setString('display_name','${d['display_name']??''}');}
  Future<void> logout() async{await (await _p).clear();}
  Future<Map<String,String>> _h() async{final t=(await _p).getString('jwt');return {'Content-Type':'application/json',if(t!=null)'Authorization':'Bearer '+t};}
  Future<dynamic> request(String method,String path,{Map<String,dynamic>? body}) async{final u=Uri.parse(baseUrl+path);final h=await _h();late http.Response r;if(method=='GET'){r=await http.get(u,headers:h);}else if(method=='POST'){r=await http.post(u,headers:h,body:jsonEncode(body??{}));}else{r=await http.delete(u,headers:h);}dynamic d;try{d=jsonDecode(r.body);}catch(_){d={'ok':false,'error':r.body};}if(r.statusCode==401){await logout();throw Exception('انتهت جلسة الدخول');}if(r.statusCode>=400||(d is Map&&d['ok']==false))throw Exception(d is Map?(d['error']??'حدث خطأ'):'حدث خطأ');return d;}
  Future<void> login(String uid,String code) async{final d=await request('POST','/api/auth/verify',body:{'telegram_user_id':int.tryParse(uid),'code':code.trim()});await saveAuth(Map<String,dynamic>.from(d['data']));}
  Future<List<dynamic>> dashboard() async=>List<dynamic>.from((await request('GET','/api/dashboard'))['data']??[]);
  Future<List<dynamic>> drivers() async=>List<dynamic>.from((await request('GET','/api/drivers'))['data']??[]);
  Future<List<dynamic>> problems({String? type,String? date,String? search}) async{final q=<String,String>{};if(type!=null&&type!='all')q['type']=type;if(date!=null)q['date']=date;if(search!=null&&search.isNotEmpty)q['search']=search;return List<dynamic>.from((await request('GET',Uri(path:'/api/problems',queryParameters:q).toString()))['data']??[]);}
  Future<Map<String,dynamic>> vehicleHistory(String v) async=>Map<String,dynamic>.from((await request('GET','/api/vehicles/'+Uri.encodeComponent(v)+'/history'))['data']);
  Future<Map<String,dynamic>> driverHistory(String id) async=>Map<String,dynamic>.from((await request('GET','/api/drivers/'+id))['data']);
  Future<void> fixProblem(int id) async{await request('POST','/api/problems/$id/fix');}
  Future<void> commentProblem(int id,String c) async{await request('POST','/api/problems/$id/comment',body:{'comment':c});}
  Future<void> convertAccident(int id) async{await request('POST','/api/problems/$id/accident');}
}