import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() => runApp(const BotIdeApp());

const bg = Color(0xFF0B1020);
const panel = Color(0xFF121A2B);
const panel2 = Color(0xFF192338);
const accent = Color(0xFF62E6B5);
const muted = Color(0xFF9AA8BD);

class BotIdeApp extends StatelessWidget {
  const BotIdeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Bot IDE',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: accent, surface: panel),
      useMaterial3: true,
      fontFamily: 'monospace',
    ),
    home: const IdeHome(),
  );
}

class BotProject {
  BotProject(this.name, this.path, this.code);
  String name;
  String path;
  String code;
}

class IdeHome extends StatefulWidget {
  const IdeHome({super.key});
  @override
  State<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends State<IdeHome> {
  final List<BotProject> projects = [];
  BotProject? selected;
  final TextEditingController editor = TextEditingController();
  final List<String> logs = [];
  bool running = false;
  bool arabic = true;
  int tab = 0;

  String tr(String ar, String en) => arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _refreshProjects();
  }

  Future<Directory> _projectDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/bot_ide_projects');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _refreshProjects() async {
    final dir = await _projectDir();
    final found = <BotProject>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.py')) {
        found.add(BotProject(entity.uri.pathSegments.last, entity.path, await entity.readAsString()));
      }
    }
    found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      projects..clear()..addAll(found);
      if (selected != null) {
        selected = projects.where((p) => p.path == selected!.path).firstOrNull;
      }
      if (selected == null && projects.isNotEmpty) selected = projects.first;
      editor.text = selected?.code ?? '';
    });
  }

  Future<void> _openProject(BotProject p) async {
    setState(() { selected = p; editor.text = p.code; tab = 0; });
  }

  Future<void> _save() async {
    if (selected == null) return;
    await File(selected!.path).writeAsString(editor.text);
    selected!.code = editor.text;
    setState(() => logs.insert(0, tr('تم حفظ ${selected!.name}', 'Saved ${selected!.name}')));
    _notify(tr('تم الحفظ', 'Saved'));
  }

  Future<void> _newProject() async {
    final controller = TextEditingController(text: 'MyBot.py');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panel,
        title: Text(tr('إنشاء بوت جديد', 'Create a new bot')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('اسم البوت.py', 'BotName.py')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(tr('إنشاء', 'Create'))),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    var safe = name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    if (!safe.toLowerCase().endsWith('.py')) safe = '$safe.py';
    final dir = await _projectDir();
    final file = File('${dir.path}/$safe');
    if (await file.exists()) {
      _notify(tr('يوجد ملف بهذا الاسم بالفعل', 'A file with that name already exists'));
      return;
    }
    final starter = '# $safe\n# Add your Telegram bot code below.\n# Keep your bot token private.\n\nTOKEN = "PASTE_YOUR_BOT_TOKEN_HERE"\n\n';
    await file.writeAsString(starter);
    await _refreshProjects();
    final p = projects.where((x) => x.path == file.path).firstOrNull;
    if (p != null) await _openProject(p);
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['py'], withData: false);
    if (result == null || result.files.single.path == null) return;
    final source = File(result.files.single.path!);
    final dir = await _projectDir();
    var filename = result.files.single.name;
    var target = File('${dir.path}/$filename');
    if (await target.exists()) {
      final base = filename.toLowerCase().endsWith('.py') ? filename.substring(0, filename.length - 3) : filename;
      filename = '${base}_imported.py';
      target = File('${dir.path}/$filename');
    }
    await target.writeAsString(await source.readAsString());
    await _refreshProjects();
    final p = projects.where((x) => x.path == target.path).firstOrNull;
    if (p != null) await _openProject(p);
  }

  void _runNotice() {
    setState(() {
      running = !running;
      logs.insert(0, running
        ? tr('وضع تجريبي فقط: تشغيل بايثون غير مفعّل بعد.', 'Preview only: Python execution is not enabled yet.')
        : tr('تم إيقاف الوضع التجريبي.', 'Preview stopped.'));
      tab = 1;
    });
    _notify(running
      ? tr('تشغيل كود Python الحقيقي يحتاج إضافة محرك بايثون.', 'A Python runtime must be added to execute code.')
      : tr('تم الإيقاف', 'Stopped'));
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() { editor.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      body: SafeArea(child: Column(children: [
        _topBar(),
        if (projects.isNotEmpty) _toolbar(),
        Expanded(child: projects.isEmpty ? _emptyState() : Row(children: [
          SizedBox(width: 150, child: _sidebar()),
          const VerticalDivider(width: 1, color: Color(0xFF253047)),
          Expanded(child: _workspace()),
        ])),
        _bottomStatus(),
      ])),
      floatingActionButton: projects.isEmpty ? null : FloatingActionButton.small(
        onPressed: _newProject, backgroundColor: accent, foregroundColor: bg, child: const Icon(Icons.add)),
    ),
  );

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: const BoxDecoration(color: panel, border: Border(bottom: BorderSide(color: Color(0xFF253047)))),
    child: Row(children: [
      Container(width: 38, height: 38,
        decoration: BoxDecoration(color: accent.withOpacity(.13), borderRadius: BorderRadius.circular(11)),
        child: const Icon(Icons.terminal, color: accent)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text('Bot IDE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        Text('PYTHON BOT WORKSPACE', style: TextStyle(fontSize: 9, color: muted, letterSpacing: 1)),
      ])),
      IconButton(tooltip: tr('العربية / English', 'العربية / English'), onPressed: () => setState(() => arabic = !arabic),
        icon: const Icon(Icons.language)),
      IconButton(tooltip: tr('استيراد ملف .py', 'Import .py file'), onPressed: _importFile, icon: const Icon(Icons.file_open)),
    ]),
  );

  Widget _emptyState() => Center(child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 88, height: 88,
        decoration: BoxDecoration(color: accent.withOpacity(.1), borderRadius: BorderRadius.circular(24)),
        child: const Icon(Icons.smart_toy_outlined, color: accent, size: 48)),
      const SizedBox(height: 22),
      Text(tr('مرحباً بك في Bot IDE', 'Welcome to Bot IDE'), textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Text(tr('ما عندكش بوتات محفوظة حالياً. أنشئ أول بوت، وبتلقى ملفاته هنا كل مرة تفتح التطبيق.',
        'You have no saved bots yet. Create your first bot and its files will appear here whenever you open the app.'),
        textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 13, height: 1.6)),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: _newProject, icon: const Icon(Icons.add),
        label: Text(tr('إنشاء بوت جديد', 'Create a new bot')),
        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: bg, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14))),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: _importFile, icon: const Icon(Icons.file_open), label: Text(tr('استيراد بوت موجود', 'Import an existing bot'))),
    ]),
  ));

  Widget _toolbar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), color: bg,
    child: Row(children: [
      _toolButton(Icons.save_outlined, tr('حفظ', 'Save'), _save),
      const SizedBox(width: 7),
      FilledButton.icon(onPressed: _runNotice,
        style: FilledButton.styleFrom(backgroundColor: running ? const Color(0xFFFF6B78) : accent, foregroundColor: bg,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10)),
        icon: Icon(running ? Icons.stop : Icons.play_arrow, size: 18), label: Text(running ? tr('إيقاف', 'Stop') : tr('تشغيل', 'Run'))),
      const SizedBox(width: 7),
      _toolButton(Icons.refresh, tr('تحديث', 'Refresh'), _refreshProjects),
    ]),
  );

  Widget _toolButton(IconData icon, String label, VoidCallback action) => OutlinedButton.icon(
    onPressed: action,
    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD8E1EF), side: const BorderSide(color: Color(0xFF2A3851)),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10)),
    icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontSize: 12)));

  Widget _sidebar() => Container(color: panel, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: const EdgeInsets.fromLTRB(12, 14, 8, 10),
      child: Text(tr('ملفات البوتات', 'BOT FILES'), style: const TextStyle(fontSize: 10, color: muted, letterSpacing: 1))),
    ...projects.map((p) => InkWell(onTap: () => _openProject(p), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      color: selected?.path == p.path ? panel2 : Colors.transparent,
      child: Row(children: [const Icon(Icons.code, size: 16, color: accent), const SizedBox(width: 7),
        Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: selected?.path == p.path ? Colors.white : muted)))])))),
    const Spacer(),
    Padding(padding: const EdgeInsets.all(8), child: TextButton.icon(onPressed: _newProject,
      icon: const Icon(Icons.add, size: 16), label: Text(tr('بوت جديد', 'New bot'), style: const TextStyle(fontSize: 11)))),
  ]));

  Widget _workspace() => Column(children: [
    Container(color: panel, child: Row(children: [
      _tabButton(tr('المحرر', 'Editor'), 0, Icons.code),
      _tabButton(tr('الطرفية', 'Terminal'), 1, Icons.terminal),
      _tabButton(tr('معلومات البوت', 'Bot info'), 2, Icons.smart_toy_outlined),
    ])),
    Expanded(child: IndexedStack(index: tab, children: [_editorPane(), _terminalPane(), _infoPane()])),
  ]);

  Widget _tabButton(String title, int index, IconData icon) => InkWell(onTap: () => setState(() => tab = index),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == index ? accent : Colors.transparent, width: 2))),
      child: Row(children: [Icon(icon, size: 14, color: tab == index ? accent : muted), const SizedBox(width: 5),
        Text(title, style: TextStyle(fontSize: 11, color: tab == index ? Colors.white : muted))])));

  Widget _editorPane() => Column(children: [
    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), color: const Color(0xFF0E1525),
      child: Row(children: [const Icon(Icons.circle, size: 8, color: Color(0xFFFFC857)), const SizedBox(width: 8),
        Expanded(child: Text(selected?.name ?? tr('لا يوجد ملف محدد', 'No file selected'), style: const TextStyle(fontSize: 12, color: muted))),
        const Text('Python', style: TextStyle(fontSize: 10, color: accent))])),
    Expanded(child: TextField(controller: editor, expands: true, maxLines: null, minLines: null, keyboardType: TextInputType.multiline,
      autocorrect: false, enableSuggestions: false,
      style: const TextStyle(fontSize: 13, height: 1.55, color: Color(0xFFDCE7F7)),
      decoration: InputDecoration(contentPadding: const EdgeInsets.all(14), border: InputBorder.none,
        hintText: tr('# اكتب كود Python هنا...', '# Write Python code here...'), hintStyle: const TextStyle(color: Color(0xFF65738A))))),
  ]);

  Widget _terminalPane() => Container(color: const Color(0xFF070B14), width: double.infinity, padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('الطرفية • المخرجات', 'TERMINAL • OUTPUT'), style: const TextStyle(color: accent, fontSize: 11, letterSpacing: 1)),
      const SizedBox(height: 12),
      Expanded(child: logs.isEmpty ? Text(tr('لا توجد مخرجات حتى الآن.', 'No output yet.'), style: const TextStyle(color: muted, fontSize: 12)) : ListView.builder(
        reverse: true, itemCount: logs.length, itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text('› ${logs[index]}', style: const TextStyle(fontSize: 11, height: 1.4, color: Color(0xFFB7C7D9)))))),
      Text(tr('تنبيه: تشغيل Python الحقيقي غير مفعّل في هذه النسخة.', 'Note: real Python execution is not enabled in this build.'),
        style: const TextStyle(color: muted, fontSize: 10)),
    ]));

  Widget _infoPane() => Padding(padding: const EdgeInsets.all(16), child: ListView(children: [
    const Icon(Icons.smart_toy_outlined, size: 42, color: accent), const SizedBox(height: 12),
    Text(selected?.name ?? tr('لا يوجد مشروع', 'No project'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    _infoRow(tr('نوع الملف', 'File type'), '.py'),
    _infoRow(tr('الحفظ على الجهاز', 'Saved locally'), tr('نعم', 'Yes')),
    _infoRow(tr('محرك Python', 'Python runtime'), tr('غير مضاف', 'Not connected')),
    _infoRow(tr('حالة تيليجرام', 'Telegram status'), tr('لم يتم التحقق', 'Not checked')),
    const SizedBox(height: 14),
    Text(tr('هذه النسخة تحفظ وتحرر ملفات البوتات، لكن يلزم إضافة محرك Python لأندرويد حتى يعمل زر التشغيل على تشغيل الكود فعلياً.',
      'This build saves and edits bot files, but an Android Python runtime is required for the Run button to execute code.'),
      style: const TextStyle(color: muted, fontSize: 12, height: 1.5)),
    const SizedBox(height: 12),
    Text(tr('الأمان: لا تشارك رمز البوت. إذا انكشف، أنشئ رمزاً جديداً من BotFather.',
      'Security: never share your bot token. If exposed, regenerate it using BotFather.'),
      style: const TextStyle(color: Color(0xFFFFC857), fontSize: 12, height: 1.5)),
  ]));

  Widget _infoRow(String label, String value) => Container(padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF253047)))),
    child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: muted, fontSize: 12))), Text(value, style: const TextStyle(fontSize: 12))]));

  Widget _bottomStatus() => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), color: const Color(0xFF101827),
    child: Row(children: [const Icon(Icons.circle, size: 7, color: accent), const SizedBox(width: 6),
      Text(tr('${projects.length} بوت', '${projects.length} bot(s)'), style: const TextStyle(fontSize: 10, color: muted)),
      const Spacer(), Text(tr('أندرويد • Bot IDE', 'Android • Bot IDE'), style: const TextStyle(fontSize: 10, color: muted))]));
}
