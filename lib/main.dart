import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'services/api_service.dart'; // ApiService'i içeri aktar
List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Kamera hatasi: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Icerik Analizoru',
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50,
      appBar: AppBar(
        title: const Text('Icerik Analizoru'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.document_scanner_outlined, size: 100, color: Colors.teal),
            const SizedBox(height: 20),
            const Text(
              'Urun içerigini tara,\nzararlı olan maddeleri öğren.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.black54),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tara'),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isCameraReady = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.ultraHigh, enableAudio: false);
    await _controller.initialize();
    await _controller.setFocusMode(FocusMode.auto);
    await _controller.setExposureMode(ExposureMode.auto);
    if (!mounted) return;
    setState(() => _isCameraReady = true);
  }

  Future<void> _taraVeAnalizeEt() async {
    if (!_isCameraReady || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await Future.delayed(const Duration(milliseconds: 1200));
      final XFile foto = await _controller.takePicture();
      final String kirpilmisYol = await _kutucuguKirp(foto.path);

      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(kirpilmisYol);
      final RecognizedText okunanMetin = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final String hamMetin = okunanMetin.text;

      if (hamMetin.trim().split(' ').length < 4) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Metin okunamadi. Yaziya daha yakin tutun.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ResultScreen(okunanMetin: hamMetin)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<String> _kutucuguKirp(String fotografYolu) async {
    final bytes = await File(fotografYolu).readAsBytes();
    final imgData = img.decodeImage(bytes);
    if (imgData == null) return fotografYolu;

    final int fw = imgData.width;
    final int fh = imgData.height;

    const double kutucukGenislikOran = 280 / 400;
    const double kutucukYukseklikOran = 160 / 700;

    final int kirpGenislik = (fw * kutucukGenislikOran).toInt();
    final int kirpYukseklik = (fh * kutucukYukseklikOran).toInt();
    final int kirpX = (fw / 2 - kirpGenislik / 2).toInt();
    final int kirpY = (fh / 2 - kirpYukseklik / 2).toInt();

    final kirpilmis = img.copyCrop(imgData, x: kirpX, y: kirpY, width: kirpGenislik, height: kirpYukseklik);

    final String yeniYol = fotografYolu.replaceAll('.jpg', '_kirpilmis.jpg');
    await File(yeniYol).writeAsBytes(img.encodeJpg(kirpilmis, quality: 100));
    return yeniYol;
  }

  @override
  void dispose() {
    if (_isCameraReady) _controller.dispose();
    super.dispose();
  }
  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Urun Etiketini Tara'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isCameraReady
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller),
                Center(
                  child: Container(
                    width: 280,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.tealAccent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const Positioned(
                  top: 16, left: 0, right: 0,
                  child: Text(
                    '8-12 cm yaklasarak tut',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                const Positioned(
                  bottom: 100, left: 0, right: 0,
                  child: Text(
                    'İçindekiler yazısını kutunun içine alınız\nve telefonu sabit tutunuz',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _taraVeAnalizeEt,
        backgroundColor: Colors.teal,
        icon: _isProcessing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.search, color: Colors.white),
        label: Text(_isProcessing ? 'Analiz ediliyor...' : 'Analiz Et', style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class ResultScreen extends StatefulWidget {
  final String okunanMetin;
  const ResultScreen({super.key, required this.okunanMetin});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  static const String _apiUrl = 'http://172.20.10.2:5013/api/Analiz/icerik';

  Map<String, dynamic>? _sonuc;
  bool _yukleniyor = true;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _apidenAnalizAl();
  }

  Future<void> _apidenAnalizAl() async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'icerik': widget.okunanMetin}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _sonuc = jsonDecode(response.body);
          _yukleniyor = false;
        });
      } else {
        setState(() {
          _hata = 'Sunucu hatasi: ${response.statusCode}';
          _yukleniyor = false;
        });
      }
    } catch (e) {
      setState(() {
        _hata = 'Bağlantı Hatası: Sunucu aktif değil.\n$e';
        _yukleniyor = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analiz Sonucu'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
        ),
      ),
      body: _yukleniyor
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.teal),
                  SizedBox(height: 16),
                  Text('SQL Veritabanından veriler çekiliyor...'),
                ],
              ),
            )
          : _hata != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off, size: 60, color: Colors.red),
                      Text(_hata!, textAlign: TextAlign.center),
                      ElevatedButton(onPressed: () => setState(() { _yukleniyor = true; _hata = null; _apidenAnalizAl(); }), child: const Text('Tekrar Dene'))
                    ],
                  ),
                )
              : _buildSonuclar(),
    );
  }

  Widget _buildSonuclar() {
    final zararlilar = (_sonuc!['zararliMaddeler'] as List);
    final temizler = (_sonuc!['temizMaddeler'] as List);
    final zararliSayisi = _sonuc!['zararliSayisi'] as int;
    final toplamSayisi = _sonuc!['toplamSayisi'] as int;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _OzetKart(zararliSayisi: zararliSayisi, toplamSayisi: toplamSayisi),
        const SizedBox(height: 20),
        if (zararlilar.isNotEmpty) ...[
          const _BaslikSatiri(ikon: Icons.warning_amber_rounded, baslik: 'Zararlı İçerikler', renk: Colors.red),
          const SizedBox(height: 8),
          ...zararlilar.map((z) => _IcerikKart(
                icerik: z['ad'],
                aciklama: z['aciklama'] ?? "Açıklama yok.",
                riskSeviyesi: z['riskSeviyesi'] ?? "BİLİNMİYOR",
                renk: Colors.red.shade50,
                ikonRenk: Colors.red,
                ikon: Icons.report_problem_outlined, // BURASI KRİTİK ÜNLEM!
              )),
          const SizedBox(height: 20),
        ],
        if (temizler.isNotEmpty) ...[
          const _BaslikSatiri(ikon: Icons.check_circle_outline, baslik: 'Temiz Maddeler', renk: Colors.green),
          const SizedBox(height: 8),
          ...temizler.map((t) => _IcerikKart(
                icerik: t.toString(),
                aciklama: 'Bu madde veri tabanımızdaki riskli maddeler arasında bulunamadı.',
                riskSeviyesi: 'GÜVENLİ',
                renk: Colors.green.shade50,
                ikonRenk: Colors.green,
                ikon: Icons.check_circle,
              )),
        ],
        const SizedBox(height: 20),
        ExpansionTile(
          title: const Text('Okunan Ham Metin', style: TextStyle(color: Colors.grey)),
          children: [Padding(padding: const EdgeInsets.all(12), child: Text(widget.okunanMetin))],
        ),
      ],
    );
  }
}

class _OzetKart extends StatelessWidget {
  final int zararliSayisi;
  final int toplamSayisi;
  const _OzetKart({required this.zararliSayisi, required this.toplamSayisi});

  @override
  Widget build(BuildContext context) {
    final bool temiz = zararliSayisi == 0;
    return Card(
      color: temiz ? Colors.green.shade100 : Colors.red.shade100,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(temiz ? Icons.verified_user : Icons.warning_rounded, size: 48, color: temiz ? Colors.green : Colors.red),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(temiz ? 'Sorunsuz İçerik' : '$zararliSayisi Riskli Madde!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: temiz ? Colors.green.shade800 : Colors.red.shade800)),
              Text('Toplam $toplamSayisi bileşen analiz edildi.'),
            ]),
          ],
        ),
      ),
    );
  }
}

class _BaslikSatiri extends StatelessWidget {
  final IconData ikon; final String baslik; final Color renk;
  const _BaslikSatiri({required this.ikon, required this.baslik, required this.renk});
  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(ikon, color: renk, size: 20), const SizedBox(width: 8), Text(baslik, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: renk))]);
  }
}

class _IcerikKart extends StatelessWidget {
  final String icerik;
  final String aciklama;
  final String riskSeviyesi;
  final Color renk;
  final Color ikonRenk;
  final IconData ikon;

  const _IcerikKart({required this.icerik, required this.aciklama, required this.riskSeviyesi, required this.renk, required this.ikonRenk, required this.ikon});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: renk,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(ikon, color: ikonRenk),
        title: Text(icerik, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Durum: $riskSeviyesi'),
        trailing: const Icon(Icons.info_outline, size: 20),
        onTap: () {
          // TIKLANINCA AÇILAN DETAY PENCERESİ (BottomSheet)
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (context) => Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(icerik.toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 8),
                  Text('Risk Analizi: $riskSeviyesi', style: TextStyle(fontWeight: FontWeight.bold, color: riskSeviyesi.contains("KRİTİK") ? Colors.red : Colors.orange)),
                  const Divider(height: 30),
                  Text(aciklama, style: const TextStyle(fontSize: 16, height: 1.5)),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}