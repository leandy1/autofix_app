import 'package:autofix/core/utils/fuente_bytes.dart';

/// Generador de UUID v4 (RFC 4122) para las primary keys de la app.
///
/// -----------------------------------------------------------------
/// POR QUE UUID Y NO EL TIMESTAMP QUE SE PROPUSO ORIGINALMENTE
/// -----------------------------------------------------------------
///
/// Se evaluaron las dos opciones y el timestamp se descarto por UNA razon que
/// no se ve hasta que hay dos dispositivos:
///
/// 1. `DateTime.now().millisecondsSinceEpoch` solo tiene ~1.7e12 valores por
///    SEGUNDO. Con dosouters.escribiendo a la vez, la probabilidad de que dos
///    citas caigan en el mismo milisegundo es real, y cuando ocurre SQLite
///    revienta con `UNIQUE constraint failed` y la cita NO SE GUARDA. Es
///    exactamente la clase de bug que no se reproduce probando en una sola
///    maquina y aparece en produccion un dia que nadie esta mirando.
///
/// 2. Un UUID v4 tiene 122 bits de entropia: la probabilidad de colision entre
///    dos dispositivos es menor que la de que caiga un rayo. Ademas el conflicto
///    se puede RESOLVER (ver `_conResolucionDeColision`) en vez de perder el
///    dato.
///
/// Lo que si se conserva del timestamp es la cualidad importante: el id se
/// genera en el CLIENTE, sin pedirle nada al servidor. Por eso la app puede
/// crear citas sin conexion y la clave nunca depende de un contador que otro
/// dispositivo pueda haber leido mal.
///
/// El precio de esta decision es que el id ya NO es un numero que se pueda
/// mostrar en pantalla. Para eso esta [codigoDeCita] en
/// `lib/features/citas/models/codigo_de_cita.dart`: el id va en la base y en
/// Firestore, y el numero que el humano lee se genera aparte.
///
/// -----------------------------------------------------------------
/// POR QUE NO EL PAQUETE `uuid`
/// -----------------------------------------------------------------
///
/// El algoritmo cabe en 30 lineas y es un estandar con la especificacion
/// escrita. Agregar la dependencia daria el mismo resultado con una version mas
/// que auditar en el `pubspec.lock`.
class Uuid {
  Uuid.conFuente(FuenteBytes fuente) : _bytes = fuente;

  /// Instancia de la app: entropia criptografica.
  static final Uuid instancia = Uuid.conFuente(bytesSeguros);

  final FuenteBytes _bytes;

  /// Ultimo id emitido en este proceso, para chocar de frente los dos casos que
  /// un generador aleatorio aun podria dejar pasar.
  ///
  /// Podria devolver dos veces los mismos 16 bytes, por mas improbable que sea,
  /// y tambien esta la ventana de la semilla del sistema. Un contador monotono de
  /// respaldo convierte esa "muy improbable" en una garantia: si el candidato
  /// choca con el anterior, se reintenta. Un id repetido es un dato perdido.
  String? _ultimo;

  /// 8-4-4-4-12 en hexadecimal, version 4, variante RFC 4122.
  ///
  ///   xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  ///            ^    ^    ^
  ///            |    |    variante (8, 9, a, b)
  ///            |    version 4
  ///            aleatorio
  ///
  /// El nibble de version va FIJO en 4 y el de variante en uno de {8,9,a,b}. No
  /// son adorno: son los dos campos que le dicen a cualquier libreria que lo lea
  /// (Python, Java, el futuro backend) que esto es un UUID v4 y no 16 bytes
  /// cualesquiera. Un generador que se los salta produce ids que otros sistemas
  /// rechazan.
  String generar() {
    for (var intento = 0; intento < _maxIntentos; intento++) {
      final candidato = _uno();
      if (candidato != _ultimo) {
        _ultimo = candidato;
        return candidato;
      }
    }

    // Camino que en la practica no se toma: habria que que el generador
    // devolviera 16 veces seguidas el mismo id. Se devuelve el ultimo conocido en
    // vez de inventar otro que podria chocar tambien.
    final base = _ultimo ?? _uno();
    _ultimo = base;
    return base;
  }

  static const int _maxIntentos = 8;

  static const String _alfabetoHex = '0123456789abcdef';

  String _uno() {
    final buffer = StringBuffer();
    for (var i = 0; i < _hexSinGuiones; i++) {
      // La posicion 12 es el nibble de version y la 16 el de variante.
      if (i == 12) {
        buffer.write('4');
      } else if (i == 16) {
        buffer.write(_alfabetoHex[8 + _bytes(4)]);
      } else {
        buffer.write(_alfabetoHex[_bytes(16)]);
      }
    }
    final plano = buffer.toString();
    return '${plano.substring(0, 8)}-${plano.substring(8, 12)}-'
        '${plano.substring(12, 16)}-${plano.substring(16, 20)}-'
        '${plano.substring(20)}';
  }

  /// 32 hexadecimales, o sea 128 bits.
  static const int _hexSinGuiones = 32;

  /// Longitud de un UUID con guiones. Es fija por formato, y el repo la usa en
  /// los tests para no comparar literales de 36 caracteres.
  static const int longitud = 36;

  /// Id de prueba, legible y reconocible como tal.
  ///
  /// **DEPRECADO v7**: Ahora los IDs de demo son UUIDs v4 validos generados por
  /// `SemillaCitasDemo._proximoUuidDemo()`. Este metodo se mantiene por compatibilidad
  /// con codigo que lo use directamente, pero no debe usarse en codigo nuevo.
  ///
  /// El prefijo `demo-` NO es un UUID valido. Usar `SemillaCitasDemo.generar()`
  /// para obtener citas con IDs de demo validos.
  @Deprecated(
    'Usar SemillaCitasDemo._proximoUuidDemo() para IDs de demo validos',
  )
  static String dePrueba(String sufijo) => 'demo-$sufijo';

  /// Prefijo comun de [dePrueba].
  ///
  /// **DEPRECADO v7**: Los IDs de demo ya no usan este prefijo.
  @Deprecated('Los IDs de demo son UUIDs v4 validos sin prefijo')
  static const String prefijoDemo = 'demo-';

  /// Conjunto de todos los IDs de demo pre-generados (UUIDs v4 validos, RFC 4122).
  ///
  /// Se generan con un RNG determinista (semilla 20261002) para que sean identicos
  /// en todas las instalaciones. Contiene 150 UUIDs, suficientes para la data de
  /// demo completa (historico 60 dias + hoy + futuro 14 dias).
  ///
  /// La sincronizacion usa este Set para saltar la data de demo sin una columna
  /// extra `es_demo`. Ver `SemillaCitasDemo.esDemo()`.
  ///
  /// Publico (sin guión bajo) para que `SemillaCitasDemo` pueda acceder a la lista
  /// ordenada y generar citas con los mismos UUIDs deterministas.
  static const Set<String> demoIds = <String>{
    '57478ebe-669d-49dd-8e57-33eff8ef53e7',
    'a94a9722-df70-4bb1-b1f5-bf7d5353a8fb',
    'f579598e-1b2c-40c3-81ee-e0b26b22d5cf',
    '03ce6cb5-a1c5-4282-b448-ba5423309d39',
    'e7b1c3f4-2d5a-46aa-b627-b7b76fcdd3f3',
    '273660f4-db0e-4a27-a183-70c65d5fc8db',
    '6cdefc78-4d46-4a32-8af7-f299a9bb7694',
    '8739d113-28d3-4379-8a6f-92f5ee4b17f4',
    'eb50e432-c3ed-4e69-90d1-3ed20cc22134',
    'bc012f53-55ab-4294-8951-5c32982b1f09',
    '0c97341c-1e01-4f87-a752-cb5ed63298cb',
    '98c267c8-324d-463f-a854-aa38191ddf28',
    'e34e7c28-5365-4cc0-a801-b02ae307965e',
    '21d6b448-83c7-47cb-8e21-efd9ea6dbfb2',
    'd07bde85-927b-4f40-b99d-2aa9e26c935f',
    '761f8f9d-c21f-4559-9e2a-24cc314f99e4',
    'bb15e483-a62a-4df4-a85f-0b3b32497954',
    'ebb868d8-4f4b-4f88-afe0-ea2cb25a0f79',
    'df8a5a1b-2078-422f-b141-39fb41f8b066',
    'ed0a434f-372c-4f8c-950b-decf27c753e4',
    '97f374e1-8108-4aec-b21b-7b48302be7f0',
    '530d1a49-2c62-4add-8406-1b5a2a7763de',
    '9ddd907d-a185-4296-a7b4-36893f5c18d1',
    'b71e272b-5070-45c3-8d89-d785c1308caf',
    '50513293-b66c-4ec9-aa16-e64b5a5679e3',
    '8c21599d-578a-49de-846f-6bc9bcb6d510',
    '1e7f5a35-46a4-41cf-99d0-33e595324dfa',
    '7f341483-5284-4774-834e-e7230e76c0d5',
    '0fe1a55f-2a3d-4bae-ad0b-455b5a2f3c6e',
    '6e6e0807-aa86-4062-8cb2-d7d52bba14cc',
    '50073e84-dc0e-4f7c-86d4-21e19fa9558d',
    'f3f7caa0-71f7-47a8-a2d6-272a3e7dc0f0',
    'e6e52f81-59de-4794-bd08-168114d54e79',
    '6dd8f8dd-16d7-441d-95f5-f0273fa34a9d',
    '355baf0a-4844-4fd1-9e56-127014079e65',
    'f48cc6a6-da07-4fc5-83a5-de29e8af3597',
    '9217897f-9d75-46a6-b297-fbfbdfabead2',
    '97f0743b-f80a-48ff-8a78-c757c26893e9',
    '4ff41901-3740-4295-901d-75981a25a368',
    'd82cce25-c820-4b6e-82b6-7d693a08fcb8',
    'db679943-5fdb-458c-8925-010d167efeec',
    '336d7ee1-16fb-48e7-8a91-829ed63d922a',
    '32bd02f8-e424-4be8-bd0b-0a8afe628ada',
    'a866d3ec-c9be-4829-8e91-cddd274fbcca',
    'a56d2673-87f9-4961-98be-f2dc57063e15',
    'ad374255-3200-4963-a058-0e7adaff1a0c',
    '07e100fd-6ab1-4537-bd2b-e7ddba6c1ce6',
    'dae55d57-0785-4564-87fc-ee75466fee0b',
    'db95d067-f275-4df3-9521-67645988b5f5',
    'fe3797b7-fbba-4efd-9878-34220c5b941d',
    'bf0b8ccc-47a9-4ea0-910b-020c08608b6a',
    '92261549-0194-4e9b-9fbd-4f93032390a8',
    '22afb09d-e45f-4e8e-86bc-abde08559133',
    '018f3984-f36a-4023-86fe-7637c9fac696',
    '28495835-07c0-4a6b-84eb-d36efad6c40d',
    'df6c8c43-a42f-46ce-b4ea-3869b24b399b',
    '957a3ef5-700e-46e5-9204-d6675ad8ece3',
    '79cc9a04-e44f-4d09-9739-ddb4b60d9f78',
    'b540482c-fded-4c77-af52-b46acb965e4f',
    '1f55ef36-17b5-4da4-8177-3c7c05ac6fc2',
    '1c6e54f4-67c8-46f3-9cc9-a014adb73a3a',
    'dc6a2003-1f3b-4e12-858b-8b969101ad1b',
    'c4faa5be-909a-46a3-b4f8-457fd4191894',
    '12c6f41b-4a4d-46c3-b49f-b6a52d5f9f13',
    '15c37e7e-785a-4003-91d0-2f89f954240e',
    '2b1c6ad7-58a7-441a-8a97-28bd822c4065',
    'a31caa3f-d3e6-4529-86dd-f71e40158192',
    '90560c05-0af6-4958-b1eb-fb773b6e5c62',
    '96faf524-192e-4755-a02c-ffcbd7adab89',
    '69d85e6f-2d7a-4100-8a2d-96e9e91920e6',
    'd5200f15-a1fe-4e68-a13b-a8606c7e4e52',
    '9aa55c3f-b5f5-4796-8b14-889bb66d01af',
    'b3ab094e-b1ba-4deb-b328-efeb6c13d1e1',
    '52b0ac80-23fe-4fd5-b15d-b57b9830d3e9',
    '0331b0ed-32a0-42ae-ad94-3b65e65585f7',
    '04dcdd8c-4ec5-4c31-8105-349414784bfb',
    '3f835502-33b2-474c-bd92-c7cbbdf77636',
    '02f2f4ee-128f-4282-9041-e72fa47aa87f',
    '29906d31-6aac-48d4-8aa4-e52e6a879c84',
    '7de7bd5c-2c25-4b9d-9652-7292dc9b373e',
    '3f19a7fb-5704-4e81-8674-b3d109caee8b',
    '524040c8-c11d-4e0c-889a-2dfc99419d54',
    'f916ac58-fc96-488e-a9cd-f24f97fc074f',
    'f3929eb7-36ee-4948-b4a0-e3bd2f95e383',
    'e82b734d-ea97-42c4-b67a-e82dafd426a3',
    'e806c8fd-9ec5-445c-a2cc-383adf550b00',
    '749af238-bf87-4e28-b70a-077049aef89f',
    'd0e88282-cebb-4bbd-806c-94d30b1b452d',
    'cf777022-91fb-439c-850e-04ad39f8202b',
    'a3aa2434-4c11-487f-912a-ac2866b53c5c',
    'aa8881ac-a235-44ed-85f5-9f4ad6080c8d',
    'c3503e2d-c297-466f-84c8-fbfa1d50a672',
    'f4b9b7a9-3ce6-4358-acdb-23ea513074b0',
    '05786aa1-b7cb-4ad1-8f4c-6b1ee139bbfd',
    '6b75eff2-168d-4385-b2c5-e0bda3a4f736',
    '5719e613-3c39-4b2c-90c2-b5eef8ce9761',
    'ab040ac9-9a22-4099-aa0f-598bec56b2b6',
    '4700ed80-14f3-4b9d-a504-db624aeddcb4',
    '0e4464d3-9b90-4ea4-bb4a-4dd462d850f5',
    '7a1d7762-3f46-4ed9-9890-224d9e9902ba',
    'f136fd89-4e00-421c-a62b-fac4ac858e88',
    'ba31ab27-2302-439f-b2d4-58c2f3338cdb',
    '95d5ada1-2a0d-4fdc-9ef0-fcd1ad0a89e8',
    'd249473c-6246-4886-bd2c-c6fee1d30fcf',
    'bc3afdb7-c96f-4c05-9dc5-2fc072a2d9da',
    '50235ccc-0772-4981-b10b-15e79d8756eb',
    '36f54e38-6395-4ff3-846c-90029d293cdd',
    'eaf8eafa-912b-4478-b201-28cab20d4dd7',
    'a7069974-3524-4c3f-8c74-fcd908f44927',
    '6b7dd4d3-342b-4632-ad11-883de118041e',
    '1cc7ec9e-5475-4412-8017-5a9721e04ca3',
    '0700fa5f-78ed-4a1f-a728-1a31c253579b',
    '9d907a98-0aa1-4720-8cd3-291c4f9df6cf',
    '77d7635b-cfec-4b35-8849-5474f2db5c33',
    'af53a730-0947-4b7f-b686-118cfff64ba6',
    'bc01d6f3-ece3-45e9-a372-8a43e9b371eb',
    'f8938559-87ae-454b-9f36-3dbff2209da7',
    '383710d1-3d4a-4f04-b76c-60287a1b8977',
    '3a713968-7387-4d39-a067-1d064e1d14f3',
    '81e753b9-5588-40ca-b209-6b7a3e3c9a3a',
    '6472b2fe-aa92-4594-bb87-4f39905d398a',
    '54cee213-16ca-4f9a-925a-1e0e9a043f28',
    'f11e686f-4b22-40a8-aeda-d80075fc77a4',
    '29abc834-013c-4496-9139-f77c6c3dedaf',
    'f284d521-d4f9-4f74-9027-ace49bbe55bb',
    'e2c7b09f-6b8a-47a9-907f-af08ded1fd1b',
    '0dedd49b-4b05-4485-a9d8-f6f4f23e8294',
    'c3885525-78e8-4a56-b24c-0264fbfb92f0',
    'cdc65450-8e1f-46f6-859b-f4ffc10bb50b',
    '8eb6b730-1bf5-463c-8184-6095f3736785',
    'a0e4c436-e8a1-46f1-a2c6-efe35d9d6267',
    'b5922d11-3c1a-49c2-9501-3b15b8f48de2',
    '4807f212-0a35-4262-b823-018d7a7a1ea3',
    'f66f1da5-5000-43fa-8c7f-e4df48c07c43',
    'de323a0b-8d16-4c62-8f09-d0235c6aac47',
    '998253b5-9c06-4a33-bed9-f1069c8ff4b9',
    'b71a918b-2936-4bab-b741-2a756d6bbe94',
    '0ebf84fa-9c60-4547-80c9-de83d56d2d9d',
    '9968c9df-309c-4351-b74e-46f4117a2729',
    'f8384400-c42d-4060-abd5-9a7398310629',
    '237dceaf-ead5-4114-972d-6a0d92849d9b',
    '410c0adc-9c35-42df-989e-e1456f78b451',
    '33583bf1-1fef-407f-bfc6-1cbca195eeca',
    'ba6d6396-7d64-4255-811f-d4989f783555',
    'd33fe0ed-fe95-48ea-9bbb-e0b8a8927e95',
    '6b4598d1-5fcf-4707-9d59-d61866236daa',
    'd75426ac-330e-4ef3-aea8-f7fd7ac3d4a6',
    'daab7ab0-96a6-426a-96be-3b22c26a4441',
    '4fdd5c11-a931-4d5f-b3c2-8b32e93eb66c',
    '3d0f7ace-9c99-4efa-a0f1-fdcf508d24ca',
    'dd1b3ced-22d8-4836-9b00-45681b968dc6',
    '0343e527-215a-487d-af3c-0874a8360c09',
    '6ec5fafe-2250-4e1a-a69b-22d1b74efd48',
    '46e27b55-8646-4d35-a2d0-cf8d17f6ff2c',
    'e46b2d81-3c04-49e1-8d52-b28d46fa19b3',
    '159fc919-c911-4364-b904-27b414174796',
    'f2f9ee29-284a-4dec-9941-a86b6e793797',
    'a21fcf36-5210-474c-a03d-7d020389034b',
    'f736288f-44e9-4a05-87bd-6e73d3f4b7c3',
    '28445475-b34d-428d-97c0-97a19308d2ed',
    '06fdd07f-3a95-4f36-a632-7377c7ff4997',
    '21983d4b-2cf3-42d5-8e11-110dc7e68dd9',
    '34999324-d974-4ce9-a619-fb87ebed7539',
    '0a36167e-59a0-4904-b526-bedd1081069f',
    '67a3894d-403c-44bc-9058-27bd2e68a7c4',
    '53d28428-9532-4bfe-acbb-efd4fe5da9d9',
    '10405ffa-9eb3-40c8-8eee-892873bcf17f',
    '3d759e89-cc6b-40dc-8f75-f6f47c2488fc',
    '3b7c67f0-e1d3-4de8-886a-474184bfba01',
    '1bda9a6f-f8bc-413d-b26f-5f9e583d980e',
    '7eb0f594-698f-486b-85a4-ed93e1c23dae',
    '94f6bff2-5912-44fa-822d-8f617eb2cd06',
    '6afba369-e583-4790-9c71-22b6f80f4654',
    '5af3252c-2551-4a2a-8e88-cc55ae9f8bf5',
    'b16df5da-eb63-42bc-a99e-ec3febd10008',
    'fec6d323-9e80-4061-879b-9c97ca8b6cd4',
    '5ed2b1a4-e368-47ba-a08a-94b3667279b2',
    '5b8485cf-797f-40de-b3d1-1b1175be56fd',
    'd6624431-a895-4cf0-859c-da92c5706a4a',
    'ff95d82c-f38e-46ff-943f-ccb0a1419c5e',
    '9bf2e128-cb17-44f2-8d50-c025cd5c9b3b',
    '61ed5764-7127-4e68-82c5-7b66e12d012a',
    '281d3f97-40c9-457a-8349-8d9b118fedc1',
    'dd1a6c2a-a398-423d-bd62-b738db803f15',
    'e91ddc0f-2734-46b2-903e-2330ce79d049',
    'f2ceac0d-879f-4621-a9f4-26ef4bf9a54c',
    'c113b60b-04eb-44d3-8e52-a33b5dc17419',
    '5f76aea9-a996-44dd-a3b7-7729c41abe7b',
    'dfd84bc5-dd46-4b94-bcea-52cb6a780fe0',
    'bb641b75-f623-4132-80cd-518c9c7b60cc',
    '8ee72c59-299b-479a-8791-4e09ef3977a2',
    'a3bcf5ee-f279-40b2-bdd0-d26f3c5e61fb',
    'f35676a5-a967-45a4-8205-599bb3bd4705',
    '153412e6-762b-44d9-a566-3d3471fba27b',
    'c1dc9cc7-90dd-45df-a3a6-82f15c5f6bc0',
    '91812156-bd28-4d6d-8f62-559e6d94d58a',
    'a3637a2c-c5ae-4376-b5ed-29dc6b01fc53',
    'b0925c8a-5b73-415b-aa70-2da1b7f87067',
    'e7bf579d-733f-484b-930a-06bc237dd2d6',
    '7205dbeb-1dd8-4ebe-9743-7a7944035675',
    '44dfecd5-6a32-4157-9cbb-0ad5143fcf86',
    'b9697f0e-2c36-4705-9940-a0b312ca9bec',
    '4bb7b172-b1ef-4f1d-bf8b-e1acebdc2b8d',
    '3a449ca0-5f77-4e90-943e-2dfa018f8520',
    '5688b00f-1655-4447-8c12-35eaf35152e6',
    '83a1fa8a-c691-4a9d-b462-199480e2b03a',
    '585fe7ff-094b-48db-90d4-41bb3e8f91ab',
    '99193b6d-3505-4f33-9fef-4208f2a965d2',
    '8bbfb10e-134f-4f4c-b3a6-270be175f2ad',
    'f35d6e14-4089-41cf-88b3-d5b4472098d8',
    '709fdc51-9512-46a2-a3ef-840b39759d14',
    'a71c9e2c-a452-415c-9670-c55edc3afca7',
    '92f01391-4fb5-4dfb-a934-a13b08fb9d91',
    '31eff65e-4741-4e9c-b2c9-c29c9aec9b3d',
    'fdd24e7a-3123-4f8c-8fe7-31918b234fbc',
    '6622bdf5-3e03-4504-89a5-15e41698f2ad',
    '5a7d4388-df2b-416c-b21d-163f9a62e06c',
    'f61aab39-1be2-4076-9648-ade918a3b69a',
    '8930b17d-1996-490c-9585-c19b7691a76d',
    'e2c5940e-08eb-4232-a797-36ac6dacea84',
    '84e2983f-4c75-4699-a321-e6793ef2e228',
    'b3bd1a5e-d62b-4053-9fe1-17511cb128af',
    '74f72e30-fadc-411c-bdea-39f31bcc56e9',
    '35f29274-8b18-46eb-b08f-baaa18c1044b',
    '0fa4391b-5f51-454a-887f-b765178a6702',
    'a7f1b1f1-4c30-4364-8784-81fecf7b0827',
    'ccf8d7bf-a3be-4c90-9b19-f7e5b56b9338',
    '088eac34-ec2c-4f78-91f1-9f1e94a23258',
    '926e9281-30a4-4bd7-b240-1a67dbf1c522',
    '135e233b-62ea-4da6-be4e-2a36398b3133',
    '024467b0-33df-496d-b7a1-d9ec92b753fc',
    '81a03c9c-402a-4b7a-8e44-fb36810f0bd7',
    '19ad40c7-6377-49d6-b066-95553033a143',
    '95c14438-a087-4698-9f39-dcb7ef3ba0e3',
    '85f421ba-698a-4e64-bd5c-f62fed43bc9f',
    '4a33b72e-3650-4e95-af28-bfac8fe96d84',
    '5aa6122b-2471-4860-afe8-ba24e0ef6243',
    '8d77df9e-cad2-433c-bd2d-b9e5369d6b01',
    '04d53832-e7d0-42ac-b7b5-5cfae4aafd76',
    'f1679a44-3095-4ee3-8661-f02e549099d5',
    '03a75a42-e4d0-4c89-b20a-f37506d8c982',
    'a8b5d059-34df-4ddf-b383-c0a5d260aff6',
    '3528e3a3-909f-406e-8d05-eefabfa2b0e3',
    '606891ed-882a-4237-ac63-e086e1ab4792',
    'dedbe736-2fcd-45f7-881f-aabf1349c8cc',
    'ee428123-d51a-41d4-b1c4-99a5378a8cde',
    '23cc825f-0cac-4aad-b3cf-d9b234412a33',
    '216ffcff-b322-4a32-82c3-922f1e12b935',
    '93a64875-684e-4485-b98c-b3052e5e73ea',
    'e68ff89f-ae39-41fb-beb8-171368e0f1ca',
    '2f615ee3-4768-493f-8a08-aab8ef010acd',
    '16a5310e-548c-4438-8d41-76a5c9b3b77f',
    'e763d4da-95fa-4925-9efc-7aba5b4d10a2',
    'c6656eca-fa3b-4be3-8a8e-fd91f149cb5d',
    '515058b9-b32c-4787-b442-4d77ea0dc968',
    '905394b0-2988-4eae-a6c8-32c889649d44',
    'de08cd3c-6b3a-4781-8507-adb1ca2e604d',
    'add5aaee-c2d7-4c56-a916-3cb37ae0f3cf',
    'b11f9485-af34-41db-86f8-137762342af5',
    '854e32cc-cf03-48c8-b265-65ffc2d0bb3c',
    '8b21fe2f-ad7f-4361-9fc1-5225b54a1d7f',
    '87c0cf46-878d-4163-bbc0-c42c3d269c28',
    'b7e18dc3-c839-434c-b23f-72f2a9ca86a2',
    'df03f3ef-693f-4d02-a829-4cb399556261',
    '1b4c67e2-acf0-4213-88b2-983c286ef678',
    'c3d144fb-2e35-4014-8e05-0c94d810e035',
    'ca05a6e3-af37-4eed-8c5e-b20b2d78a726',
    'a9694052-fee8-408d-bd01-5678b11178cc',
    '4af685d7-8762-410a-9e66-2cdee6434afe',
    'fd6687f6-6283-4c74-aa29-3f35380feb25',
    '8d9a02f2-9cc6-43ef-90f1-11f1764776aa',
    '501ccd63-27fb-4599-b55c-2e689b254b84',
    '4a596349-7ca5-4033-ad4b-da322b380212',
    '013258c3-2ebc-4fd2-be93-f89ec85a2dda',
    '155db001-5572-4b01-b0e6-3216b6af9350',
    '63b7bc54-2538-4a65-8683-81adf1086371',
    'e9796bbe-a70b-49c3-988a-6d52e4dee365',
    '5d01cfbe-2b10-4f4c-a819-c7854e8b6729',
    'd9368a8c-ea7c-4c64-a8a7-a95a8df0ac0d',
    '33f3c00f-de15-43e3-a46f-c801ddcc966a',
    'a363773a-1baf-49aa-addc-e4999f2fa1fb',
    '7444e698-07b3-459a-b7a5-6a49266dd78c',
    '7fc66f4a-372c-4c8d-85c3-e861a6f33897',
    'be0e9192-a779-4b59-8879-23159944e587',
    'b767612b-c5b1-4ed2-a268-ad7822d499de',
    '3ba2f624-1cde-44d1-bfb2-4d7b27222a30',
    'fc4fb9d7-f1ae-497c-bbfe-894f48dc29d7',
    'b3416a93-21ce-4abc-b888-e8ec1570e8c0',
    '24f4e75e-e372-4970-a0d4-cedf2bc0b587',
    '599e471f-12f4-43ae-874a-fea2a00840af',
    '95e35f62-0e12-4b11-bd09-9816e59060d3',
    'f0d32f1a-b7bd-4d7c-836e-b83e467ad245',
    '4decdbd6-ac85-47eb-8c57-3269cc1f961f',
    'db788887-d584-4356-9d7e-d12282f71021',
    'c4c57fb7-d0f7-4c4c-905f-0ddc382103de',
    '05d58d73-2319-4bdf-be95-1ee547d942b1',
    '9e993642-3c8b-4e81-b0a2-9e681e26ab6e',
    '34a2a79c-1358-4138-9455-1b42383f8107',
    'fc0c845c-14d7-47db-8a1a-5ca0c56f581d',
    '6f5ae2f2-b16f-4e04-b3e3-3644db64058a',
  };

  /// `true` si el id pertenece a la data de demo (UUID v4 valido pre-generado).
  ///
  /// v7: NO usa prefijo `demo-`. Usa pertenencia al Set de 150 UUIDs v4 validos
  /// pre-generados con RNG determinista (semilla 20261002). Esto permite que la
  /// sincronizacion salte la data de demo sin una columna extra `es_demo`.
  static bool esDemo(String id) => demoIds.contains(id);

  /// Si el texto tiene la FORMA de un UUID v4 de 36 caracteres.
  ///
  /// No valida la entropia (eso no se puede), solo el formato: 8-4-4-4-12 en
  /// hexadecimal, con el nibble de version en 4. Los repositorios lo usan para
  /// no mandar a Firestore una fila importada cuyo id sea otra cosa.
  static bool tieneFormaDeUuid(String? texto) {
    if (texto == null || texto.length != longitud) return false;
    final partes = texto.split('-');
    if (partes.length != 5) return false;
    const longitudes = <int>[8, 4, 4, 4, 12];
    for (var i = 0; i < 5; i++) {
      if (partes[i].length != longitudes[i]) return false;
      if (!RegExp(r'^[0-9a-f]+$').hasMatch(partes[i])) return false;
    }
    return partes[2][0] == '4';
  }
}
