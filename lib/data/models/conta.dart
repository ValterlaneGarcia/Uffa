class Conta {
  final String id;
  String nome;
  double limite;
  double saldo;
  double saldoInicial;
  String tipo;
  String cor;
  String? icone;
  int? diaVencimento;
  int? diaFechamento;

  Conta({
    required this.id,
    required this.nome,
    required this.limite,
    this.saldo = 0,
    this.saldoInicial = 0,
    required this.tipo,
    required this.cor,
    this.icone,
    this.diaVencimento,
    this.diaFechamento,
  });

  double get disponivel => tipo == 'credito' ? limite - saldo : saldo;
  double get percentUsed => limite > 0 ? (saldo / limite).clamp(0.0, 1.0) : 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'limite': limite,
        'saldo': saldo,
        'saldo_inicial': saldoInicial,
        'tipo': tipo,
        'cor': cor,
        'icone': icone,
        'dia_vencimento': diaVencimento,
        'dia_fechamento': diaFechamento,
      };

  factory Conta.fromMap(Map<String, dynamic> m) => Conta(
        id: m['id'],
        nome: m['nome'],
        limite: (m['limite'] as num).toDouble(),
        saldo: (m['saldo'] as num? ?? 0).toDouble(),
        saldoInicial: (m['saldo_inicial'] as num? ?? 0).toDouble(),
        tipo: m['tipo'],
        cor: m['cor'],
        icone: m['icone'],
        diaVencimento: m['dia_vencimento'] as int?,
        diaFechamento: m['dia_fechamento'] as int?,
      );

  Conta copyWith({
    String? nome,
    double? limite,
    double? saldo,
    double? saldoInicial,
    String? tipo,
    String? cor,
    String? icone,
    int? diaVencimento,
    int? diaFechamento,
  }) =>
      Conta(
        id: id,
        nome: nome ?? this.nome,
        limite: limite ?? this.limite,
        saldo: saldo ?? this.saldo,
        saldoInicial: saldoInicial ?? this.saldoInicial,
        tipo: tipo ?? this.tipo,
        cor: cor ?? this.cor,
        icone: icone ?? this.icone,
        diaVencimento: diaVencimento ?? this.diaVencimento,
        diaFechamento: diaFechamento ?? this.diaFechamento,
      );
}

// Known banks with colors and icons
class BancoInfo {
  final String nome;
  final String cor;
  final String icone;

  const BancoInfo({required this.nome, required this.cor, required this.icone});
}

const List<BancoInfo> bancosConhecidos = [
  BancoInfo(nome: 'Nubank', cor: '8A05BE', icone: 'nubank'),
  BancoInfo(nome: 'Inter', cor: 'FF6B00', icone: 'inter'),
  BancoInfo(nome: 'Itaú', cor: 'EC7000', icone: 'itau'),
  BancoInfo(nome: 'Bradesco', cor: 'CC0000', icone: 'bradesco'),
  BancoInfo(nome: 'Santander', cor: 'EC0000', icone: 'santander'),
  BancoInfo(nome: 'Caixa', cor: '005CA9', icone: 'caixa'),
  BancoInfo(nome: 'Banco do Brasil', cor: 'F7E002', icone: 'bb'),
  BancoInfo(nome: 'C6 Bank', cor: '1D1D1B', icone: 'c6'),
  BancoInfo(nome: 'XP', cor: '000000', icone: 'xp'),
  BancoInfo(nome: 'BTG', cor: '022169', icone: 'btg'),
  BancoInfo(nome: 'PicPay', cor: '21C25E', icone: 'picpay'),
  BancoInfo(nome: 'Mercado Pago', cor: '009EE3', icone: 'mercadopago'),
  BancoInfo(nome: 'Outros', cor: '6B7280', icone: 'outros'),
];