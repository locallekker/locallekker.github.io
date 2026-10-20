import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:local_lekker/widgets/branded_app_bar.dart';
import 'dart:async';
import '../../services/supabase_service.dart';
import '../../services/navigation_service.dart';
import '../../services/promotion_campaign_service.dart';
import 'widgets/otp_verification_dialog.dart';
import 'welcome_page.dart';

class MembersSignupPage extends StatefulWidget {
  const MembersSignupPage({super.key});

  @override
  State<MembersSignupPage> createState() => _MembersSignupPageState();
}

class _MembersSignupPageState extends State<MembersSignupPage> {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _streetController = TextEditingController();
  final _suburbController = TextEditingController();
  String? _selectedSuburb;
  String? _selectedCity;
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  DateTime? _selectedDate;
  bool _showDobValidationError = false;
  String? _selectedGender;
  String? _selectedEthnicity;
  String? _selectedProvince;

  static const String _customSuburbOption = 'Other (enter manually)';

  // Flag to trigger navigation to payment screen
  bool _shouldNavigateToPayment = false;

  // Email check state
  Timer? _emailDebounce;
  bool _checkingEmail = false;
  bool _emailIsActive = false;
  bool _emailIsDeactivated = false;
  String? _resumingProfileUserId;
  // True when an existing profile was found but signup never completed
  // (no active subscription / not a TP member). We let the user resume
  // signup (re-verify OTP + pay) instead of forcing them to sign in,
  // which would require a password they never finished setting.
  bool _isResumingSignup = false;

  // Promo eligibility detected from the entered email
  Map<String, dynamic>? _promoEligibility;

  // Store reference to ScaffoldMessenger to avoid context issues
  late ScaffoldMessengerState _scaffoldMessenger;

  final List<String> _genders = ['Male', 'Female', 'Other'];
  final List<String> _ethnicities = [
    'Black',
    'White',
    'Coloured',
    'Indian',
    'Other',
  ];
  final List<String> _provinces = [
    'Eastern Cape',
    'Free State',
    'Gauteng',
    'KwaZulu-Natal',
    'Limpopo',
    'Mpumalanga',
    'Northern Cape',
    'North West',
    'Western Cape',
  ];

  final Map<String, List<String>> _citiesByProvince = {
    'Eastern Cape': [
      'Bhisho',
      'Butterworth',
      'Cradock',
      'East London',
      'Fort Beaufort',
      'Graaff-Reinet',
      'Grahamstown (Makhanda)',
      'Jeffreys Bay',
      'King William\'s Town',
      'Komani (Queenstown)',
      'Mthatha',
      'Port Alfred',
      'Port Elizabeth (Gqeberha)',
      'Queenstown',
      'Uitenhage',
    ],
    'Free State': [
      'Bethlehem',
      'Bloemfontein',
      'Botshabelo',
      'Harrismith',
      'Kroonstad',
      'Parys',
      'Phuthaditjhaba',
      'Sasolburg',
      'Thaba Nchu',
      'Virginia',
      'Welkom',
      'Zastron',
    ],
    'Gauteng': [
      'Alberton',
      'Benoni',
      'Boksburg',
      'Brakpan',
      'Bronkhorstspruit',
      'Carletonville',
      'Centurion',
      'Edenvale',
      'Germiston',
      'Johannesburg',
      'Kempton Park',
      'Krugersdorp',
      'Midrand',
      'Muldersdrif',
      'Pretoria',
      'Randburg',
      'Randfontein',
      'Roodepoort',
      'Sandton',
      'Soweto',
      'Springs',
      'Tembisa',
      'Vanderbijlpark',
      'Vereeniging',
      'Westonaria',
    ],
    'KwaZulu-Natal': [
      'Amanzimtoti',
      'Ballito',
      'Durban',
      'Empangeni',
      'Eshowe',
      'Howick',
      'Kokstad',
      'KwaDukuza (Stanger)',
      'Ladysmith',
      'Margate',
      'Newcastle',
      'Pietermaritzburg',
      'Pinetown',
      'Port Shepstone',
      'Richards Bay',
      'Tongaat',
      'Ulundi',
      'Umhlanga',
      'Umlazi',
      'Vryheid',
    ],
    'Limpopo': [
      'Bela-Bela',
      'Burgersfort',
      'Giyani',
      'Lephalale',
      'Louis Trichardt (Makhado)',
      'Mokopane',
      'Musina',
      'Phalaborwa',
      'Polokwane',
      'Thohoyandou',
      'Tzaneen',
    ],
    'Mpumalanga': [
      'Barberton',
      'Bethal',
      'Ermelo',
      'Evander',
      'Lydenburg (Mashishing)',
      'Middelburg',
      'Nelspruit (Mbombela)',
      'Secunda',
      'Standerton',
      'White River',
      'Witbank (Emalahleni)',
    ],
    'Northern Cape': [
      'De Aar',
      'Colesberg',
      'Douglas',
      'Kathu',
      'Kimberley',
      'Kuruman',
      'Prieska',
      'Springbok',
      'Upington',
    ],
    'North West': [
      'Brits',
      'Hartbeespoort',
      'Klerksdorp',
      'Lichtenburg',
      'Mahikeng',
      'Potchefstroom',
      'Rustenburg',
      'Vryburg',
    ],
    'Western Cape': [
      'Beaufort West',
      'Bellville',
      'Brackenfell',
      'Cape Town',
      'Claremont',
      'Constantia',
      'Fish Hoek',
      'George',
      'Goodwood',
      'Hermanus',
      'Knysna',
      'Lansdowne',
      'Mitchells Plain',
      'Mossel Bay',
      'Oudtshoorn',
      'Paarl',
      'Plettenberg Bay',
      'Saldanha',
      'Somerset West',
      'Stellenbosch',
      'Strand',
      'Swellendam',
      'Tokai',
      'Vredenburg',
      'Wellington',
      'Worcester',
    ],
  };

  final Map<String, List<String>> _suburbsByCity = {
    // ── Eastern Cape ─────────────────────────────────────────────────────────
    'Bhisho': ['Bhisho CBD', 'Bhisho Hospital Area', 'Dimbaza', 'Mdantsane', 'Potsdam'],
    'Butterworth': ['Butterworth CBD', 'Gcuwa', 'Centani', 'Idutywa', 'Ngqamakhwe'],
    'Cradock': ['Cradock CBD', 'Michausdal', 'Lingelihle', 'Clarendon', 'Sunnyridge'],
    'East London': [
      'Abbotsford', 'Amalinda', 'Arcadia', 'Baysville', 'Beacon Bay',
      'Beacon Bay North', 'Berea', 'Bonza Bay', 'Braelyn', 'Buffalo Flats',
      'Cambridge', 'Chiselhurst', 'Clarendon', 'Cove Rock', 'Duncan Village',
      'East London CBD', 'East London North', 'Eldorado', 'Farrar', 'Frere',
      'Gonubie', 'Greenfields', 'Greengate', 'Healthways', 'Hemingways',
      'Kidds Beach', 'King\'s Court', 'Leaches Bay', 'Longcroft', 'Mdantsane',
      'Morningside', 'Mount Pleasant', 'Nahoon', 'Nahoon Mouth', 'Northcrest',
      'Oxford', 'Parkside', 'Quigney', 'Reeston', 'Scenery Park',
      'Selborne', 'Southernwood', 'Stirling', 'Sunnyridge', 'Sweethome',
      'Vincent', 'West Bank', 'Westbank', 'Wilsonia', 'Woodbrook',
    ],
    'Fort Beaufort': ['Fort Beaufort CBD', 'Bhofolo', 'Newtown', 'Debe Nek', 'Seymour'],
    'Graaff-Reinet': ['Graaff-Reinet CBD', 'Kroonvale', 'Umasizakhe', 'Oakdale', 'Sunvalley'],
    'Grahamstown (Makhanda)': [
      'Grahamstown CBD', 'Extension 9', 'Fingo Village', 'Joza',
      'Makana', 'Riebeeck East', 'Tantyi', 'Vukani',
    ],
    'Jeffreys Bay': [
      'Aston Bay', 'Fountains', 'Jeffreys Bay CBD', 'Kabeljouws',
      'Noorsekloof', 'Paradise Beach', 'Pellsrus', 'Sea Vista', 'Wavecrest',
    ],
    'King William\'s Town': [
      'King William\'s Town CBD', 'Bhisho', 'Ginsberg', 'Newlands',
      'Quakenbush', 'Zwelitsha',
    ],
    'Komani (Queenstown)': [
      'Ezibeleni', 'Ilitha', 'Komani CBD', 'Mlungisi',
      'Queenstown CBD', 'Sada', 'Whittlesea',
    ],
    'Mthatha': [
      'Bhongweni', 'Corana', 'Fort Gale', 'Fortgale', 'Ikwezi',
      'Mthatha CBD', 'Ncambedlana', 'Ngangelizwe', 'Northcrest',
      'Southernwood', 'Summerstrand', 'Umtata Central',
    ],
    'Port Alfred': [
      'Cannon Rocks', 'Kariega', 'Kenton-on-Sea', 'Kowie West',
      'Ndlambe', 'Nemato', 'Port Alfred CBD', 'Southernwood',
    ],
    'Port Elizabeth (Gqeberha)': [
      'Algoa Park', 'Arcadia', 'Baakens Valley', 'Bethelsdorp', 'Bluewater Bay',
      'Booysens Park', 'Central', 'Charlo', 'Cleary Park', 'Cotswold',
      'Crusader', 'Deal Party', 'Despatch', 'Die Wilgers', 'Fernglen',
      'Framesby', 'Gelvandale', 'Glendinningvale', 'Greenacres', 'Greenbushes',
      'Helenvale', 'Humansdorp', 'Humewood', 'Kabega Park', 'Kuyga',
      'Linton Grange', 'Mill Park', 'Motherwell', 'Mount Road', 'New Brighton',
      'Newton Park', 'North End', 'Parsons Hill', 'Perridgevale', 'Port Elizabeth CBD',
      'Rowallan Park', 'Sherwood', 'South End', 'Summerstrand', 'Theescombe',
      'Uitenhage Road', 'Veronica', 'Walmer', 'Westering', 'Westview', 'Zwide',
    ],
    'Queenstown': ['Ezibeleni', 'Ilitha', 'Komani', 'Mlungisi', 'Queenstown CBD', 'Sada'],
    'Uitenhage': [
      'Cannon Hill', 'Despatch', 'Duncanville', 'Govan Mbeki',
      'KwaNobuhle', 'Rosedale', 'Uitenhage CBD', 'Uitenhage North',
    ],

    // ── Free State ────────────────────────────────────────────────────────────
    'Bethlehem': ['Bethlehem CBD', 'Bohlokong', 'Fort Naudé', 'Phiritona', 'Pretoriuskloof'],
    'Bloemfontein': [
      'Arboretum', 'Batho', 'Bayswater', 'Bergmanshoogte', 'Bloemfontein CBD',
      'Bloubergrant', 'Botshabelo', 'Brandwag', 'Cecilia', 'Dan Pienaar',
      'Ehrlich Park', 'Fauna', 'Fleurdal', 'Gardenia Park', 'Generaal De Wet',
      'Grasslands', 'Groenvlei', 'Heidedal', 'Hospitaalpark', 'Kagisanong',
      'Kiepersol', 'Langenhoven Park', 'Lourierpark', 'Mangaung', 'Mountainside',
      'Naval Hill', 'Navalsig', 'Oranjesig', 'Park West', 'Pentagon Park',
      'Pellissier', 'Rayton', 'Roodewal', 'Rustdene', 'Tempe',
      'Universitas', 'Uitsig', 'Waverley', 'Westdene', 'Wild Olive',
      'Wilgehof', 'Woodland Hills', 'Zenahof',
    ],
    'Botshabelo': ['Botshabelo CBD', 'Unit C', 'Unit E', 'Unit F', 'Unit H', 'Unit M', 'Unit R'],
    'Harrismith': ['Harrismith CBD', 'Intabazwe', 'Swinburne', 'Sterkspruit', 'Witsieshoek'],
    'Kroonstad': ['Kroonstad CBD', 'Maokeng', 'Ntha', 'Seeisoville', 'Vredepark'],
    'Parys': ['Parys CBD', 'Tumahole', 'Schoonspruit', 'Sonlandpark'],
    'Phuthaditjhaba': ['Phuthaditjhaba CBD', 'Makoane', 'Tshiame', 'Witsieshoek'],
    'Sasolburg': ['Sasolburg CBD', 'Deneysville', 'Metsimaholo', 'Vaalpark', 'Zamdela'],
    'Thaba Nchu': ['Thaba Nchu CBD', 'Mokwena', 'Ratlou', 'Selosesha'],
    'Virginia': ['Virginia CBD', 'Meloding', 'Thabong'],
    'Welkom': ['Bronville', 'Dagbreek', 'Flamingo', 'Majuba', 'Meer En See', 'Thabong', 'Welkom CBD'],
    'Zastron': ['Zastron CBD', 'Matlwangtlwang', 'Naledi'],

    // ── Gauteng ───────────────────────────────────────────────────────────────
    'Alberton': [
      'Alberton CBD', 'Alrapark', 'Brackendowns', 'Brackenhurst', 'Eden Glen',
      'Florentia', 'Glenanda', 'Kliprivier', 'New Redruth', 'Ormonde',
      'Roodekrans', 'Roodekop', 'Sonderwater', 'Verwoerdpark',
    ],
    'Benoni': [
      'Actonville', 'Apex', 'Benoni CBD', 'Brentwood', 'Crystal Park',
      'Daveyton', 'Etwatwa', 'Farrarmere', 'Lakefield', 'Northmead',
      'Rynfield', 'Strathavon', 'Tom Jones', 'Wattville',
    ],
    'Boksburg': [
      'Bartlett', 'Boksburg CBD', 'Boksburg East', 'Boksburg North',
      'Cedarwood', 'Dawn Park', 'Devland', 'Fulcrum', 'Impala Park',
      'Parkrand', 'Ravenswood', 'Sunward Park', 'Vosloorus',
    ],
    'Brakpan': [
      'Apex', 'Brakpan CBD', 'Brakpan North', 'Dalpark', 'Geluksdal',
      'Leachville', 'Middelvlei', 'Tsakane',
    ],
    'Bronkhorstspruit': ['Bronkhorstspruit CBD', 'Ekangala', 'Rethabiseng', 'Zithobeni'],
    'Carletonville': ['Carletonville CBD', 'Khutsong', 'Oberholzer', 'Wedela'],
    'Centurion': [
      'Amberfield', 'Centurion CBD', 'Clubview', 'Cornwall Hill',
      'Die Hoewes', 'Eldoraigne', 'Erasmia', 'Highveld', 'Irene',
      'Lyttelton', 'Meyerspark', 'Monavoni', 'Pierre van Ryneveld',
      'Rooihuiskraal', 'Rooihuiskraal North', 'Thatchfield', 'Wierda Park', 'Zwartkop',
    ],
    'Edenvale': [
      'Bedfordview', 'Eastleigh', 'Eden Glen', 'Edenvale CBD',
      'Greenstone', 'Hurlyvale', 'Modderfontein', 'Norkem Park',
    ],
    'Germiston': [
      'Bedfordview', 'Dinwiddie', 'Driehoek', 'Elspark',
      'Germiston CBD', 'Lambton', 'Mineralia', 'Primrose',
      'Symhurst', 'Terenure',
    ],
    'Johannesburg': [
      'Alexandra', 'Auckland Park', 'Bassonia', 'Bedfordview', 'Berea',
      'Bertrams', 'Bez Valley', 'Birdhaven', 'Bordeaux', 'Bosmont',
      'Braamfontein', 'Bramley', 'Brixton', 'Burghersdorp', 'Chartwell',
      'Claremont', 'Craighall', 'Craighall Park', 'Crosby', 'Crown Gardens',
      'Crown Mines', 'Cyrildene', 'Dainfern', 'Daveytown', 'Dunkeld',
      'Eldorado Park', 'Emmarentia', 'Fairland', 'Fairlands', 'Ferndale',
      'Florida', 'Fordsburg', 'Forest Town', 'Fourways', 'Glenanda',
      'Glenvista', 'Greenside', 'Highlands North', 'Hillbrow', 'Houghton',
      'Hurlingham', 'Hyde Park', 'Illovo', 'Johannesburg CBD', 'Jouberton',
      'Kelvin', 'Kensington', 'Killarney', 'Kyriadene', 'Linden',
      'Linksfield', 'Lyndhurst', 'Malvern', 'Mayfair', 'Melrose',
      'Melrose Arch', 'Melville', 'Midrand', 'Millpark', 'Mondeor',
      'Morningside', 'Mulbarton', 'Newlands', 'Newtown', 'Norwood',
      'Oaklands', 'Observatory', 'Orchards', 'Orange Grove', 'Parkdene',
      'Parkhurst', 'Parkmore', 'Parktown', 'Parkview', 'Parkwood',
      'Primrose Hill', 'Randburg', 'Ridgeway', 'Rivonia', 'Robertsham',
      'Roosevelt Park', 'Rosebank', 'Rosettenville', 'Sandton', 'Sandringham',
      'Saxonwold', 'Selby', 'Sophiatown', 'South Hills', 'Soweto',
      'Stafford', 'Strathavon', 'Sydenham', 'Turffontein', 'Victory Park',
      'Waverley', 'Westcliff', 'Westdene', 'Wynberg', 'Yeoville',
    ],
    'Kempton Park': [
      'Birch Acres', 'Edleen', 'Esther Park', 'Kempton Park CBD',
      'Norkem Park', 'Pomona', 'Rhodesfield', 'Spartan', 'Terenure',
    ],
    'Krugersdorp': [
      'Azaadville', 'Chamdor', 'Dandypark', 'Greenhills', 'Kagiso',
      'Krugersdorp CBD', 'Krugersdorp North', 'Krugersdorp West',
      'Munsieville', 'Randfontein Road', 'West Krugersdorp',
    ],
    'Midrand': [
      'Carlswald', 'Cosmo City', 'Dainfern', 'Halfway Gardens', 'Halfway House',
      'Kyalami', 'Kyalami Estate', 'Midrand CBD', 'Noordwyk', 'Waterfall',
      'Waterfall City', 'Woodmead',
    ],
    'Muldersdrif': ['Blue Hills', 'Cosmo City', 'Diepsloot', 'Muldersdrif', 'Ruimsig'],
    'Pretoria': [
      'Akasia', 'Annlin', 'Arcadia', 'Ashlea Gardens', 'Atteridgeville',
      'Baileys Muckleneuk', 'Berea', 'Booysens', 'Brooklyn', 'Capital Park',
      'Celtis Ridge', 'Centurion', 'Clubview', 'Constantia Park', 'Danville',
      'Doringkloof', 'East Lynne', 'Eersterust', 'Equestria', 'Erasmia',
      'Faerie Glen', 'Garsfontein', 'Gezina', 'Groenkloof', 'Hatfield',
      'Irene', 'Kilner Park', 'Laudium', 'Lukasrand', 'Lynnwood',
      'Lynnwood Glen', 'Mamelodi', 'Meyerspark', 'Menlo Park', 'Menlyn',
      'Montana', 'Moreleta Park', 'Muckleneuk', 'Murrayfield', 'Olympus',
      'Pretoria CBD', 'Pretoria East', 'Pretoria North', 'Pretoria West',
      'Proclamation Hill', 'Queenswood', 'Rietondale', 'Rietfontein',
      'Silverton', 'Sinoville', 'Soshanguve', 'Sunnyside', 'The Willows',
      'Tijger Vallei', 'Valhalla', 'Villieria', 'Waterkloof', 'Waterkloof Heights',
      'Waterkloof Park', 'Waterkloof Ridge', 'Wierda Park', 'Wingate Park', 'Wonderboom',
    ],
    'Randburg': [
      'Blairgowrie', 'Bordeaux', 'Bryanston', 'Cosmo City', 'Darrenwood',
      'Diepsloot', 'Douglasdale', 'Ferndale', 'Fontainebleau', 'Hurlingham',
      'Jukskei Park', 'Kensington B', 'Linden', 'Lonehill', 'Magaliessig',
      'Malibongwe Ridge', 'Moret', 'Northcliff', 'Petervale', 'Randburg CBD',
      'Robindale', 'Roosevelt Park', 'Strijdompark', 'Windsor', 'Windsor East',
    ],
    'Randfontein': ['Mohlakeng', 'Randgate', 'Randfontein CBD', 'Toekomsrus', 'Wedela'],
    'Roodepoort': [
      'Dobsonville', 'Eagle Canyon', 'Florida', 'Florida Hills', 'Florida Lake',
      'Honeydew', 'Helderkruin', 'Little Falls', 'Northgate', 'Northriding',
      'Princess', 'Roodepoort CBD', 'Ruimsig', 'Weltevreden Park',
    ],
    'Sandton': [
      'Atholl', 'Benmore Gardens', 'Bryanston', 'Chartwell', 'Dainfern',
      'Dunkeld', 'Fourways', 'Hyde Park', 'Illovo', 'Kelvin',
      'Kramerville', 'Lonehill', 'Melrose Arch', 'Morningside', 'Parkmore',
      'Paulshof', 'Rivonia', 'Rosebank', 'Sandown', 'Sandton CBD',
      'Sandhurst', 'Sunninghill', 'Wierda Valley', 'Woodmead', 'Wynberg',
    ],
    'Soweto': [
      'Chiawelo', 'Devland', 'Diepkloof', 'Dobsonville', 'Dube',
      'Emndeni', 'Emdeni', 'Fleurhof', 'Ikageng', 'Jabulani',
      'Kagiso', 'Klipspruit', 'Mapetla', 'Meadowlands', 'Molapo',
      'Moletsane', 'Moroka', 'Mofolo', 'Naledi', 'Noordgesig',
      'Orlando East', 'Orlando West', 'Phiri', 'Pimville',
      'Protea Glen', 'Protea North', 'Senaoane', 'Slovoville',
      'Tladi', 'White City', 'Zola', 'Zondi',
    ],
    'Springs': [
      'Bakerton', 'Casseldale', 'Daggafontein', 'Geduld',
      'KwaThema', 'Selcourt', 'Springs CBD', 'Strubenvale', 'Welgedacht',
    ],
    'Tembisa': ['Clayville', 'Isando', 'Kaalfontein', 'Rabie Ridge', 'Tembisa CBD'],
    'Vanderbijlpark': [
      'Bedworth Park', 'Boipatong', 'Fochville', 'Roshnee',
      'Rust ter Vaal', 'Vanderbijlpark CBD', 'Vanderbijlpark SE',
    ],
    'Vereeniging': [
      'Boipatong', 'Peacehaven', 'Sharpeville', 'Stretford',
      'Three Rivers', 'Unitas Park', 'Vereeniging CBD',
    ],
    'Westonaria': ['Bekkersdal', 'Hillshaven', 'Libanon', 'Westonaria CBD'],

    // ── KwaZulu-Natal ─────────────────────────────────────────────────────────
    'Amanzimtoti': [
      'Amanzimtoti CBD', 'Doonside', 'Illovo Beach', 'Isipingo',
      'Isipingo Beach', 'Kingsburgh', 'Umkomaas', 'Warner Beach',
    ],
    'Ballito': [
      'Ballito CBD', 'Compensation', 'Dolphin Coast', 'Salt Rock',
      'Shaka\'s Rock', 'Sheffield Beach', 'Simbithi Eco Estate', 'Tinley Manor',
    ],
    'Durban': [
      'Amanzimtoti', 'Ashley', 'Atholl Heights', 'Avoca', 'Berea',
      'Bluff', 'Bonela', 'Carrington Heights', 'Chatsworth', 'Chesterville',
      'Clare Estate', 'Clairwood', 'Clermont', 'Congella', 'Cato Crest',
      'Cato Manor', 'Davenport', 'Desainagar', 'Duff\'s Road', 'Durban CBD',
      'Durban North', 'Effingham', 'Essenwood', 'Felixton', 'Glenmore',
      'Glenwood', 'Greyville', 'Hillcrest', 'Hillary', 'Isipingo',
      'KwaMashu', 'Labourville', 'Lamontville', 'Malvern',
      'Manor Gardens', 'Maydon Wharf', 'Merewent', 'Mobeni', 'Montclair',
      'Morningside', 'Musgrave', 'New Germany', 'Newlands East', 'Newlands West',
      'Ntuzuma', 'Overport', 'Phoenix', 'Pinetown', 'Point',
      'Prospecton', 'Queensburgh', 'Reservoir Hills', 'Ridgeside',
      'Rossburgh', 'Sea View', 'Sherwood', 'Springfield', 'Stamford Hill',
      'Sydenham', 'Tollgate', 'Umbilo', 'Umhlatuzana', 'Umhlanga',
      'Umbogavango', 'Umlazi', 'Verulam', 'Westville', 'Woodlands',
    ],
    'Empangeni': [
      'Allandale', 'Empangeni CBD', 'Empangeni Rail', 'Felixton',
      'Hayfields', 'KwaHlabisa', 'Ngwelezane',
    ],
    'Eshowe': ['Eshowe CBD', 'Entumeni', 'Mdlalose', 'Nkwaleni', 'Sundumbili'],
    'Howick': ['Howick CBD', 'Merrivale', 'Midmar', 'Mpophomeni', 'Thornville'],
    'Kokstad': ['Bhongweni', 'Franklin', 'Kokstad CBD', 'Mount Currie'],
    'KwaDukuza (Stanger)': [
      'Compensation', 'Groutville', 'KwaDukuza', 'Ndwedwe', 'Stanger CBD',
    ],
    'Ladysmith': [
      'Danskraal', 'Emnambithi', 'Ezakheni', 'Ladysmith CBD',
      'Steadville', 'Sunnybrook',
    ],
    'Margate': ['Margate CBD', 'Ramsgate', 'Shelly Beach', 'Southbroom', 'St Michaels-on-Sea', 'Uvongo'],
    'Newcastle': [
      'Amajuba', 'Balgwan', 'Incandu', 'Madadeni', 'Newcastle CBD',
      'Normandien', 'Osizweni', 'Whiteridge',
    ],
    'Pietermaritzburg': [
      'Ashburton', 'Bisley', 'Chase Valley', 'Clarendon', 'Copesville',
      'Eastwood', 'Edendale', 'Hayfields', 'Hilton', 'Howick',
      'Jacobs', 'Lincoln Meade', 'Montrose', 'Msunduzi', 'Napierville',
      'Northdale', 'Pelham', 'Pietermaritzburg CBD', 'Plessislaer',
      'Prestbury', 'Scottsville', 'Sobantu', 'Southgate',
      'Town Bush Valley', 'Wembley', 'Willowfontein', 'Woodlands',
    ],
    'Pinetown': [
      'Cato Ridge', 'Cowies Hill', 'Emberton', 'Gillitts', 'Hammarsdale',
      'Hillcrest', 'New Germany', 'Outer West', 'Pinetown CBD', 'Westmead',
    ],
    'Port Shepstone': [
      'Gamalakhe', 'Leisure Bay', 'Marburg', 'Paddock',
      'Port Shepstone CBD', 'Shelly Beach', 'Trafalgar',
    ],
    'Richards Bay': [
      'Alkantstrand', 'Arboretum', 'Brackenham', 'Esikhaleni',
      'Meer En See', 'Meerensee', 'Nseleni', 'Richards Bay CBD',
      'Tuzi Gazi', 'Veldenvlei',
    ],
    'Tongaat': ['Hambanati', 'Maidstone', 'Ndwedwe', 'Tongaat CBD', 'Verulam'],
    'Ulundi': ['eDumbe', 'Nongoma', 'Ulundi CBD', 'Vryheid Road'],
    'Umhlanga': [
      'La Lucia', 'La Mercy', 'Mount Edgecombe', 'Umhlanga CBD',
      'Umhlanga Rocks', 'Umhlanga Ridge', 'Umhlanga New Town Centre',
    ],
    'Umlazi': ['Isipingo Hills', 'Lamontville', 'Umlazi K', 'Umlazi Township', 'Umlazi V'],
    'Vryheid': ['Bhekuzulu', 'Enyokeni', 'Hlobane', 'Vryheid CBD'],

    // ── Limpopo ───────────────────────────────────────────────────────────────
    'Bela-Bela': ['Bela-Bela CBD', 'Bela-Bela Extension', 'Rabelani', 'Spa Park', 'Tikwana'],
    'Burgersfort': ['Burgersfort CBD', 'Ga-Mphahlele', 'Jane Furse', 'Steelpoort'],
    'Giyani': ['Block A', 'Block B', 'Block J', 'Giyani CBD', 'Malamulele'],
    'Lephalale': ['Lephalale CBD', 'Marapong', 'Onverwacht', 'Steenbokpan'],
    'Louis Trichardt (Makhado)': [
      'Dzanani', 'Louis Trichardt', 'Makhado CBD',
      'Makhado Extension', 'Tshilamba', 'Vuwani',
    ],
    'Mokopane': ['Ga-Mapela', 'Mahwelereng', 'Mapela', 'Mokopane CBD', 'Mokopane Extension'],
    'Musina': ['Messina', 'Musina CBD', 'Nancefield', 'Tshipise', 'Vhufuli'],
    'Phalaborwa': ['Hans Merensky', 'Lulekani', 'Namakgale', 'Phalaborwa CBD', 'Phalaborwa Extension'],
    'Polokwane': [
      'Bendor', 'Bendor Park', 'CBD', 'Classicview', 'Flora Park',
      'Hospital Park', 'Ivy Park', 'Ladanna', 'Nirvana', 'Penina Park',
      'Platinum Park', 'Polokwane CBD', 'Polokwane Extension', 'Safari',
      'Seshego', 'Sterpark', 'Superbia', 'Welgelegen', 'Westernburg',
    ],
    'Thohoyandou': [
      'Shayandima', 'Sibasa', 'Thohoyandou CBD', 'Tshikhudini', 'Tshilwavhusiku',
    ],
    'Tzaneen': [
      'Aqua Park', 'Haenertsburg', 'Lenyenye', 'Nkowankowa',
      'Tzaneen CBD', 'Tzaneen Extension',
    ],

    // ── Mpumalanga ────────────────────────────────────────────────────────────
    'Barberton': ['Barberton CBD', 'De Kaap', 'Emjindini', 'Fairview', 'Mountainview'],
    'Bethal': ['Bethal CBD', 'Embalenhle', 'Morgenzon'],
    'Ermelo': ['Ermelo CBD', 'Ermelo Extension', 'Mataffin', 'Wesselton'],
    'Evander': ['Evander CBD', 'Kinross', 'Leslie', 'Trichardt'],
    'Lydenburg (Mashishing)': ['Lydenburg CBD', 'Mashishing', 'Merino', 'Paardekop'],
    'Middelburg': [
      'Aerorand', 'Blinkpan', 'Hendrina', 'Kwaza', 'Mhluzi',
      'Middelburg CBD', 'Middelburg Extension', 'Middelburg North', 'Nasaret',
    ],
    'Nelspruit (Mbombela)': [
      'Alkmaar', 'Boskop', 'Crocodile Valley', 'Kamagugu', 'Kanyamazane',
      'Mbombela CBD', 'Mataffin', 'Nelspruit CBD', 'Nelspruit Extension',
      'Nelspruit North', 'Riverside', 'Rocky Drift', 'Sonheuwel',
      'Steiltes', 'West Acres', 'White River',
    ],
    'Secunda': ['Highveld', 'Lebohang', 'Secunda CBD', 'Trichardt'],
    'Standerton': ['Morgenzon', 'Sakhile', 'Standerton CBD', 'Volksrust'],
    'White River': ['Hazyview', 'Tonga', 'White River CBD', 'White River Extension'],
    'Witbank (Emalahleni)': [
      'Del Judor', 'Emalahleni', 'Ext 25', 'Highveld Park',
      'Klipfontein', 'Nkangala', 'Witbank CBD',
    ],

    // ── Northern Cape ─────────────────────────────────────────────────────────
    'Colesberg': ['Colesberg CBD', 'Kwezane', 'Norvalspont', 'Philipstown'],
    'De Aar': ['De Aar CBD', 'De Aar Junction', 'Nonzwakazi', 'Vosburg'],
    'Douglas': ['Bridgetown', 'Douglas CBD', 'Papierfonten'],
    'Kathu': ['Dibeng', 'Kathu CBD', 'Olifantshoek', 'Sesheng'],
    'Kimberley': [
      'Beaconsfield', 'Cassandra', 'CBD', 'Colville', 'De Beers',
      'Florianville', 'Galeshewe', 'Greenpoint', 'Hadison Park',
      'Herlear', 'Hillcrest', 'Homevale', 'Kimberley CBD',
      'Monument Heights', 'New Park', 'Platfontein', 'Roodepan', 'Ritchie',
    ],
    'Kuruman': ['Bankhara-Bodulong', 'Kagung', 'Kuruman CBD', 'Mothibistad'],
    'Prieska': ['Niekerkshoop', 'Prieska CBD', 'Vosburg'],
    'Springbok': ['Carolusberg', 'Kingsleytown', 'Springbok CBD', 'Steinkopf'],
    'Upington': ['Keimoes', 'Louisvale', 'Paballelo', 'Upington CBD', 'Upington North'],

    // ── North West ────────────────────────────────────────────────────────────
    'Brits': ['Brits CBD', 'Brits Extension', 'Elandsrand', 'Ikageleng', 'Xanadu'],
    'Hartbeespoort': ['Hartbeespoort CBD', 'Ifafi', 'Kosmos', 'Melodie', 'Schoemansville'],
    'Klerksdorp': [
      'Alabama', 'Flamwood', 'Jouberton', 'Klerksdorp CBD',
      'Meiringspark', 'Orkney', 'Park Rynie', 'Stilfontein', 'Wilkoppies',
    ],
    'Lichtenburg': ['Boikhutso', 'Lichtenburg CBD', 'Tlhabologang'],
    'Mahikeng': ['Boitekong', 'Danville', 'Mahikeng CBD', 'Mmabatho', 'Montshiwa', 'Ramatlabama'],
    'Potchefstroom': [
      'Ikageng', 'Miederpark', 'Mohadin', 'Potchefstroom CBD',
      'Promosa', 'Tlokwe', 'Vyfhoek',
    ],
    'Rustenburg': [
      'Boitekong', 'Cashan', 'Geelhoutpark', 'Javelin', 'Kanana',
      'Meriting', 'Protea Park', 'Rustenburg CBD', 'Safari Gardens',
      'Seraleng', 'Tlhabane', 'Tlhabane West', 'Waterfall East',
    ],
    'Vryburg': ['Huhudi', 'Matlheng', 'Reivilo', 'Vryburg CBD'],

    // ── Western Cape ──────────────────────────────────────────────────────────
    'Beaufort West': ['Beaufort West CBD', 'Hillside', 'Oudtshoorn Road', 'Rustdene'],
    'Bellville': [
      'Bellville CBD', 'Bellville South', 'Bothasig', 'Durbanville',
      'Eversdal', 'Kenridge', 'Oakdale', 'Stikland', 'Tyger Valley', 'Unibell',
    ],
    'Brackenfell': ['Brackenfell CBD', 'Brackenfell South', 'Protea Heights', 'Sonstraal', 'Sonstraal Heights'],
    'Cape Town': [
      'Athlone', 'Atlantis', 'Bakoven', 'Bantry Bay', 'Bellville',
      'Bergvliet', 'Bishop Lavis', 'Bishopscourt', 'Bloubergrant',
      'Bloubergstrand', 'Bo-Kaap', 'Bonteheuwel', 'Brooklyn',
      'Camps Bay', 'Cape Town CBD', 'Century City', 'Claremont',
      'Clifton', 'Clovelly', 'Constantia', 'Crawford',
      'De Waterkant', 'Delft', 'Diep River', 'Durbanville',
      'Epping', 'Elfindale', 'Fish Hoek', 'Fresnaye',
      'Gardens', 'Glencairn', 'Gordon\'s Bay', 'Grassy Park',
      'Green Point', 'Gugulethu', 'Hanover Park', 'Harfield Village',
      'Heathfield', 'Hermanus', 'Hout Bay', 'Kalksteenfontein',
      'Kenilworth', 'Khayelitsha', 'Kommetjie', 'Kreupelbosch',
      'Kraaifontein', 'Kuils River', 'Kirstenhof', 'Langa',
      'Lansdowne', 'Lavender Hill', 'Llandudno', 'Lotus River',
      'Matroosfontein', 'Meadowridge', 'Milnerton', 'Mitchell\'s Plain',
      'Mowbray', 'Muizenberg', 'Newlands', 'Noordhoek',
      'Nyanga', 'Observatory', 'Ocean View', 'Oranjezicht',
      'Ottery', 'Parow', 'Pelican Park', 'Philippi',
      'Pinelands', 'Plumstead', 'Retreat', 'Rondebosch',
      'Rondebosch East', 'Ruyterwacht', 'Salt River', 'Sea Point',
      'Simon\'s Town', 'Somerset West', 'Southfield', 'Steenberg',
      'Strand', 'Sun Valley', 'Sunnydale', 'Sunset Beach',
      'Table View', 'Tamboerskloof', 'Thornton', 'Tokai',
      'Tygerdal', 'Tygerberg', 'Vredehoek', 'Wetton',
      'Westlake', 'Woodstock', 'Wynberg', 'Zonnebloem',
    ],
    'Claremont': ['Claremont CBD', 'Harfield Village', 'Kenilworth', 'Lansdowne', 'Newlands', 'Rondebosch'],
    'Constantia': ['Bishopscourt', 'Constantia Valley', 'Kreupelbosch', 'Tokai', 'Wynberg'],
    'Fish Hoek': ['Fish Hoek CBD', 'Glencairn', 'Kommetjie', 'Ocean View', 'Simon\'s Town', 'Sun Valley'],
    'George': [
      'Blanco', 'Conville', 'Denneoord', 'Dormehls Drift', 'Fancourt',
      'George CBD', 'George South', 'Heatherlands', 'Lawaaikamp',
      'Loerie Park', 'Pacaltsdorp', 'Thembalethu',
    ],
    'Goodwood': ['Bishop Lavis', 'Elsies River', 'Goodwood CBD', 'Monte Vista', 'Vasco'],
    'Hermanus': [
      'Fernkloof', 'Hawston', 'Hermanus CBD', 'Hemel en Aarde',
      'Onrus', 'Sandbaai', 'Vermont', 'Voëlklip', 'Westcliff',
    ],
    'Knysna': [
      'Concordia', 'Hornlee', 'Knysna CBD', 'Knysna Heads', 'Leisure Isle',
      'Rheenendal', 'Sedgefield', 'Thesen Islands',
    ],
    'Lansdowne': ['Claremont', 'Crawford', 'Kenilworth', 'Lansdowne', 'Southfield'],
    'Mitchells Plain': [
      'Beacon Valley', 'Colorado', 'Eastridge', 'Lentegeur',
      'Mitchells Plain CBD', 'Portland', 'Rocklands',
    ],
    'Mossel Bay': [
      'Dana Bay', 'De Bakke', 'Diaz Beach', 'George Road',
      'Great Brak River', 'Hartenbos', 'KwaNonqaba', 'Little Brak River', 'Mossel Bay CBD',
    ],
    'Oudtshoorn': ['Bridgton', 'Dysselsdorp', 'Oudtshoorn CBD', 'Toekomsrus', 'Westdene'],
    'Paarl': [
      'Dal Josafat', 'Mbekweni', 'Paarl CBD', 'Paarl East', 'Paarl North',
      'Wellington Road', 'Windmeul',
    ],
    'Plettenberg Bay': [
      'Bitou', 'Kranshoek', 'Nature\'s Valley', 'Plettenberg Bay CBD',
      'Robberg Beach', 'The Crags',
    ],
    'Saldanha': ['Diazville', 'Hopefield', 'Jacobs Bay', 'Langebaan', 'Middelpos', 'Saldanha CBD'],
    'Somerset West': [
      'Broadlands', 'Firgrove', 'Gordon\'s Bay', 'Helderberg',
      'Lwandle', 'Macassar', 'Somerset West CBD', 'Strand',
    ],
    'Stellenbosch': [
      'Cloetesville', 'Dalsig', 'De Zalze', 'Die Boord',
      'Franschhoek', 'Idasvallei', 'Kayamandi', 'Mostertsdrift',
      'Paradyskloof', 'Stellenbosch CBD', 'Technopark', 'Universiteitsoord', 'Welgevonden',
    ],
    'Strand': ['Gordons Bay', 'Lwandle', 'Macassar', 'Strand CBD'],
    'Swellendam': ['Buffeljagsrivier', 'Railton', 'Swellendam CBD'],
    'Tokai': ['Constantia', 'Kirstenhof', 'Lakeside', 'Steenberg', 'Tokai'],
    'Vredenburg': ['Hopefield', 'Louwville', 'Saldanha', 'Vredenburg CBD'],
    'Wellington': ['Dal Josafat', 'Mbekweni', 'Wellington CBD', 'Wellington North'],
    'Worcester': [
      'Avian Park', 'De Wet', 'Nkqubela', 'Rawsonville',
      'Roodewal', 'Sandringham', 'Worcester CBD', 'Zweletemba',
    ],
  };

  List<String> _getSuburbsForCity(String? city) {
    if (city == null || city.isEmpty) return const <String>[];

    final suburbs = List<String>.from(
      _suburbsByCity[city] ?? const <String>['Central', 'CBD'],
    );

    if (!suburbs.contains(_customSuburbOption)) {
      suburbs.add(_customSuburbOption);
    }

    return suburbs;
  }

  String _resolvedSuburb() {
    if (_selectedSuburb == _customSuburbOption) {
      return _suburbController.text.trim();
    }

    return (_selectedSuburb ?? '').trim();
  }

  bool _hasAllRequiredFields() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    final street = _streetController.text.trim();
    final contact = _contactController.text.trim();
    final suburb = _resolvedSuburb();

    return email.isNotEmpty &&
        RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email) &&
        password.trim().isNotEmpty &&
        confirmPassword.trim().isNotEmpty &&
        password == confirmPassword &&
        name.isNotEmpty &&
        surname.isNotEmpty &&
        _selectedDate != null &&
        _selectedGender != null &&
        _selectedEthnicity != null &&
        _selectedProvince != null &&
        _selectedCity != null &&
        suburb.isNotEmpty &&
        street.isNotEmpty &&
        contact.isNotEmpty;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Store reference to ScaffoldMessenger to avoid context issues in callbacks
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _emailDebounce?.cancel();
    _nameController.dispose();
    _surnameController.dispose();
    _streetController.dispose();
    _suburbController.dispose();

    _contactController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Handle navigation to payment screen after OTP verification
    if (_shouldNavigateToPayment) {
      _shouldNavigateToPayment = false; // Reset flag
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _proceedToPayment();
      });
    }

    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Member Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  helperText: _emailIsDeactivated
                      ? 'We found your deactivated account and prefilled your details.'
                      : _emailIsActive
                      ? 'Existing active account detected. Redirecting to sign in.'
                      : null,
                  suffixIcon: _checkingEmail
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _emailIsActive
                      ? const Icon(Icons.login, color: Colors.green)
                      : _emailIsDeactivated
                      ? const Icon(Icons.restart_alt, color: Colors.orange)
                      : null,
                ),
                keyboardType: TextInputType.emailAddress,
                onChanged: _onEmailChanged,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return 'Please enter your email';
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
                    return 'Please enter a valid email';
                  }
                  if (_emailIsActive) {
                    return 'This email already has an active account. Please sign in instead.';
                  }
                  return null;
                },
              ),
              _buildPromoBanner(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Create Password',
                  helperText: '${_passwordController.text.length}/8 characters',
                  helperStyle: TextStyle(
                    color: _passwordController.text.length >= 8
                        ? Colors.green
                        : null,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _passwordController.text.length >= 8
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _passwordController.text.length >= 8
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
                obscureText: true,
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final password = value ?? '';
                  if (password.trim().isEmpty) {
                    return 'Please enter a password';
                  }
                  if (password.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                ),
                obscureText: true,
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const Divider(height: 32),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value?.trim().isEmpty ?? true
                  ? 'Please enter your name'
                  : null,
              ),
              TextFormField(
                controller: _surnameController,
                decoration: const InputDecoration(labelText: 'Surname'),
                validator: (value) => value?.trim().isEmpty ?? true
                  ? 'Please enter your surname'
                  : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedDate == null
                          ? 'Select Date of Birth'
                          : 'DOB: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                    ),
                  ),
                  TextButton(
                    onPressed: _showDatePicker,
                    child: const Text('Pick Date'),
                  ),
                ],
              ),
              if (_showDobValidationError && _selectedDate == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Please select your date of birth',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: _selectedGender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: _genders.map((gender) {
                  return DropdownMenuItem(value: gender, child: Text(gender));
                }).toList(),
                onChanged: (value) => setState(() => _selectedGender = value),
                validator: (value) =>
                    value == null ? 'Please select your gender' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _selectedEthnicity,
                decoration: const InputDecoration(labelText: 'Ethnicity'),
                items: _ethnicities.map((ethnicity) {
                  return DropdownMenuItem(
                    value: ethnicity,
                    child: Text(ethnicity),
                  );
                }).toList(),
                onChanged: (value) =>
                    setState(() => _selectedEthnicity = value),
                validator: (value) =>
                    value == null ? 'Please select your ethnicity' : null,
              ),
              DropdownButtonFormField<String>(
                value: _selectedProvince,
                decoration: const InputDecoration(labelText: 'Province'),
                items: _provinces.map((province) {
                  return DropdownMenuItem(
                    value: province,
                    child: Text(province),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedProvince = value;
                    _selectedCity = null;
                    _selectedSuburb = null;
                    _suburbController.clear();
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select your province' : null,
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedProvince),
                value: _selectedCity,
                decoration: const InputDecoration(labelText: 'City'),
                items: (_selectedProvince != null
                        ? _citiesByProvince[_selectedProvince!] ?? []
                        : <String>[])
                    .map((city) {
                  return DropdownMenuItem(
                    value: city,
                    child: Text(city),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCity = value;
                    _selectedSuburb = null;
                    _suburbController.clear();
                  });
                },
                validator: (value) =>
                    value == null ? 'Please select your city' : null,
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedCity),
                value: _selectedSuburb,
                decoration: const InputDecoration(labelText: 'Suburb'),
                items: _getSuburbsForCity(_selectedCity).map((suburb) {
                  return DropdownMenuItem(
                    value: suburb,
                    child: Text(suburb),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSuburb = value;
                    if (value == _customSuburbOption) {
                      _suburbController.clear();
                    } else {
                      _suburbController.text = value ?? '';
                    }
                  });
                },
                validator: (value) {
                  if (value == null) return 'Please select your suburb';
                  if (value == _customSuburbOption &&
                      _suburbController.text.trim().isEmpty) {
                    return 'Please enter your suburb';
                  }
                  return null;
                },
              ),
              if (_selectedSuburb == _customSuburbOption)
                TextFormField(
                  controller: _suburbController,
                  decoration: const InputDecoration(
                    labelText: 'Enter Suburb',
                    hintText: 'Type your suburb name',
                  ),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? 'Please enter your suburb'
                      : null,
                ),
              TextFormField(
                controller: _streetController,
                decoration: const InputDecoration(labelText: 'Street Address'),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Please enter your street address'
                    : null,
              ),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(labelText: 'Contact Number'),
                keyboardType: TextInputType.phone,
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Please enter your contact number'
                    : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _createAccount,
                child: const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onEmailChanged(String value) {
    _emailDebounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _checkingEmail = false;
        _emailIsActive = false;
        _emailIsDeactivated = false;
        _resumingProfileUserId = null;
      });
      return;
    }

    _emailDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() {
        _checkingEmail = true;
        _emailIsActive = false;
        _emailIsDeactivated = false;
        _isResumingSignup = false;
        _resumingProfileUserId = null;
      });

      // Check if there's a profile (active or deactivated)
      final profile = await SupabaseService.instance.getProfileByEmail(trimmed);
      if (!mounted) return;

      if (profile != null) {
        final isDeactivated = profile['is_deactivated'] == true;

        if (!isDeactivated) {
          // Use the auth-account check, not subscription state, to decide
          // whether this is an existing account. Members can have pending or
          // inactive subscriptions and still be valid returning users.
          final authExists = await SupabaseService.instance
              .checkEmailExists(trimmed);
          if (!mounted) return;

          if (authExists) {
            // Allow likely abandoned signups to resume in the signup flow.
            // This avoids forcing users to sign in when they never finished
            // payment/subscription activation after OTP.
            final role = (profile['role'] as String?)?.trim().toLowerCase();
            final subscription =
                (profile['subscription'] as String?)?.trim().toLowerCase();
            final isTpMember = profile['is_tp_member'] == true;

            final isLikelyAbandonedMemberSignup =
                role == 'member' &&
                !isTpMember &&
                (subscription == null ||
                    subscription.isEmpty ||
                    subscription == 'pending' ||
                    subscription == 'inactive');

            if (!isLikelyAbandonedMemberSignup) {
              // Existing active/reactivating account - redirect to sign in.
              setState(() {
                _checkingEmail = false;
                _emailIsActive = true;
              });
              await _redirectToSignIn(trimmed);
              return;
            }
          }

          // Abandoned signup - prefill the form and let the member
          // resume (re-verify OTP, then pay). The auth user already
          // exists, so OtpVerificationDialog will be told to re-send
          // the OTP without creating a duplicate account.
          _logger.i(
            'Found abandoned signup for email: $trimmed. Resuming signup.',
          );
          _prefillFromProfile(profile);
          setState(() {
            _checkingEmail = false;
            _emailIsActive = false;
            _isResumingSignup = true;
            _resumingProfileUserId = profile['id'] as String?;
          });

          await _showResumeSignupPaymentDialog();
          return;
        }

        // Deactivated account - autofill from profile
        _logger.i('Found deactivated member for email: $trimmed. Autofilling.');
        _prefillFromProfile(profile);
        setState(() {
          _checkingEmail = false;
          _emailIsDeactivated = true;
        });

        // Show welcome back message for deactivated members
        _scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Welcome back! We found your previous details and autofilled the form.',
            ),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      // No profile found - new member
      setState(() {
        _checkingEmail = false;
        _emailIsActive = false;
        _emailIsDeactivated = false;
        _isResumingSignup = false;
        _resumingProfileUserId = null;
      });

      // Instantly check if this email is on an admin-created promo list
      final promo =
          await PromotionCampaignService().checkEligibilityForEmail(
        email: trimmed,
      );
      if (!mounted) return;
      setState(() {
        _promoEligibility = promo;
      });
    });
  }

  Widget _buildPromoBanner() {
    final promo = _promoEligibility;
    if (promo == null) return const SizedBox.shrink();

    final name = (promo['name'] as String?) ?? 'Special Offer';
    final freeMonths = (promo['free_months'] as int?) ?? 0;
    final initialCents = (promo['initial_charge_cents'] as int?) ?? 100;
    final renewalCents = (promo['renewal_charge_cents'] as int?) ?? 9900;

    final initialStr = (initialCents / 100).toStringAsFixed(2);
    final renewalStr = (renewalCents / 100).toStringAsFixed(2);

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.celebration, color: Colors.green.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You qualify for the $name promo!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  freeMonths > 0
                      ? 'Pay R$initialStr signup and enjoy $freeMonths month(s) free. After that, your subscription auto-renews at R$renewalStr/month using the card you save during signup.'
                      : 'Pay R$initialStr signup and enjoy a free lifetime membership.',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _prefillFromProfile(Map<String, dynamic> profile) {
    _nameController.text = (profile['name'] ?? '') as String;
    _surnameController.text = (profile['surname'] ?? '') as String;
    _streetController.text = (profile['street'] ?? '') as String;
    final profileSuburb = profile['suburb'] as String?;
    _contactController.text = (profile['contact'] ?? '') as String;
    _selectedProvince = profile['province'] as String?;
    final profileCity = profile['city'] as String?;
    if (_selectedProvince != null && profileCity != null) {
      final cities = _citiesByProvince[_selectedProvince!] ?? [];
      _selectedCity = cities.contains(profileCity) ? profileCity : null;
    }
    if (_selectedCity != null && profileSuburb != null) {
      final suburbs = _getSuburbsForCity(_selectedCity);
      if (suburbs.contains(profileSuburb)) {
        _selectedSuburb = profileSuburb;
        _suburbController.text = profileSuburb;
      } else {
        _selectedSuburb = _customSuburbOption;
        _suburbController.text = profileSuburb;
      }
    } else {
      _selectedSuburb = null;
      _suburbController.text = profileSuburb ?? '';
    }
    _selectedGender = profile['gender'] as String?;
    _selectedEthnicity = profile['ethnicity'] as String?;

    final dob = profile['date_of_birth'] as String?;
    if (dob != null) {
      _selectedDate = DateTime.tryParse(dob);
    }

    // Keep email controller as-is (user input), but ensure trimmed casing
    if (profile['email'] is String) {
      _emailController.text = (profile['email'] as String).trim();
    }
  }

  Future<void> _redirectToSignIn(String email) async {
    _scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text(
          'This email already has an active account. Redirecting to sign in.',
        ),
        duration: Duration(seconds: 3),
      ),
    );

    await Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) =>
            WelcomePage(openSignInOnLoad: true, prefillEmail: email.trim()),
      ),
      (route) => false,
    );
  }

  Future<void> _showResumeSignupPaymentDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Signup Found'),
          content: const Text(
            'Welcome back! 👋 It looks like you started signing up before. '
            'We\'ve restored your details — just proceed to complete your registration.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Stay Here'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // Route through sign-in so terms are shown/enforced after auth,
                // then post-login navigation handles terms → payment automatically.
                final email = _emailController.text.trim();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WelcomePage(
                      openSignInOnLoad: true,
                      prefillEmail: email.isNotEmpty ? email : null,
                    ),
                  ),
                  (route) => false,
                );
              },
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDatePicker() async {
    if (kIsWeb) {
      final now = DateTime.now();
      final initialDate = _selectedDate ?? DateTime(now.year - 18, now.month, now.day);
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(1900, 1, 1),
        lastDate: now,
      );
      if (picked != null) {
        setState(() {
          _selectedDate = picked;
          _showDobValidationError = false;
        });
      }
      return;
    }

    final DateTime now = DateTime.now();
    int selectedDay = _selectedDate?.day ?? (now.day - 1);
    int selectedMonth = _selectedDate?.month ?? now.month;
    int selectedYear = _selectedDate?.year ?? (now.year - 18);

    // Ensure selectedDay is valid for the selected month/year
    int maxDays = _getDaysInMonth(selectedYear, selectedMonth);
    if (selectedDay > maxDays) {
      selectedDay = maxDays;
    }

    await showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              height: 300,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Text(
                          'Select Date of Birth',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final selectedDate = DateTime(
                              selectedYear,
                              selectedMonth,
                              selectedDay,
                            );
                            this.setState(() {
                              _selectedDate = selectedDate;
                              _showDobValidationError = false;
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        // Day picker
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            scrollController: FixedExtentScrollController(
                              initialItem: selectedDay - 1,
                            ),
                            onSelectedItemChanged: (int index) {
                              setState(() {
                                selectedDay = index + 1;
                              });
                            },
                            children: List<Widget>.generate(
                              _getDaysInMonth(selectedYear, selectedMonth),
                              (int index) {
                                return Center(child: Text('${index + 1}'));
                              },
                            ),
                          ),
                        ),
                        // Month picker
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            scrollController: FixedExtentScrollController(
                              initialItem: selectedMonth - 1,
                            ),
                            onSelectedItemChanged: (int index) {
                              setState(() {
                                selectedMonth = index + 1;
                                // Adjust day if necessary when month changes
                                int maxDays = _getDaysInMonth(
                                  selectedYear,
                                  selectedMonth,
                                );
                                if (selectedDay > maxDays) {
                                  selectedDay = maxDays;
                                }
                              });
                            },
                            children: List<Widget>.generate(12, (int index) {
                              final monthNames = [
                                'Jan',
                                'Feb',
                                'Mar',
                                'Apr',
                                'May',
                                'Jun',
                                'Jul',
                                'Aug',
                                'Sep',
                                'Oct',
                                'Nov',
                                'Dec',
                              ];
                              return Center(child: Text(monthNames[index]));
                            }),
                          ),
                        ),
                        // Year picker
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 40,
                            scrollController: FixedExtentScrollController(
                              initialItem: selectedYear - 1900,
                            ),
                            onSelectedItemChanged: (int index) {
                              setState(() {
                                selectedYear = 1900 + index;
                                // Adjust day if necessary when year changes (leap year)
                                int maxDays = _getDaysInMonth(
                                  selectedYear,
                                  selectedMonth,
                                );
                                if (selectedDay > maxDays) {
                                  selectedDay = maxDays;
                                }
                              });
                            },
                            children: List<Widget>.generate(125, (int index) {
                              return Center(child: Text('${1900 + index}'));
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int _getDaysInMonth(int year, int month) {
    if (month == 2) {
      // February - check for leap year
      if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
        return 29;
      } else {
        return 28;
      }
    } else if ([4, 6, 9, 11].contains(month)) {
      return 30;
    } else {
      return 31;
    }
  }

  void _createAccount() async {
    if (_emailIsActive) {
      await _redirectToSignIn(_emailController.text);
      return;
    }

    final hasAllRequiredFields = _hasAllRequiredFields();
    final isFormValid = _formKey.currentState?.validate() ?? false;

    if (!hasAllRequiredFields || !isFormValid) {
      setState(() {
        _showDobValidationError = _selectedDate == null;
      });

      _logger.w('Signup blocked: Required fields are incomplete');
      if (mounted) {
        _scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Please complete all required fields before continuing.',
            ),
          ),
        );
      }
      return;
    }

    if (_showDobValidationError) {
      setState(() {
        _showDobValidationError = false;
      });
    }

    if (_formKey.currentState?.validate() ?? false) {
      _logger.i('User signup initiated - showing OTP method selection');
      // Do NOT call signUpWithOtp here. Let the user choose their OTP
      // delivery method and click "Send OTP" in the dialog first.
      _showOtpVerificationDialog();
    } else {
      _logger.w('Form validation failed');
    }
  }

  void _showOtpVerificationDialog() {
    final suburb = _resolvedSuburb();

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => OtpVerificationDialog(
        email: _emailController.text,
        phoneNumber: _contactController.text,
        isResumeSignup: _isResumingSignup,
        userMetadata: {
          'user_type': 'member',
          'name': _nameController.text,
          'surname': _surnameController.text,
          'street': _streetController.text,
          'suburb': suburb,
          'city': _selectedCity,
          'province': _selectedProvince,
          'contact': _contactController.text,
          'gender': _selectedGender,
          'ethnicity': _selectedEthnicity,
          'date_of_birth': _selectedDate?.toIso8601String(),
          'temp_password': _passwordController.text,
        },
        onVerificationSuccess: (String? verifiedUserId) async {
          _logger.i('OTP verification successful, userId: $verifiedUserId');

          final uid =
              verifiedUserId ??
              SupabaseService.instance.client.auth.currentUser?.id;

          _logger.i('Final user ID for profile creation: $uid');
          _logger.i(
            'Current user from Supabase: ${SupabaseService.instance.client.auth.currentUser}',
          );
          _logger.i(
            'Current user metadata: ${SupabaseService.instance.client.auth.currentUser?.userMetadata}',
          );

          if (uid == null) {
            _logger.e('Could not determine user id after verification');
            return;
          }

          // Set the password after OTP verification
          try {
            final tempPassword =
                SupabaseService
                        .instance
                        .client
                        .auth
                        .currentUser
                        ?.userMetadata?['temp_password']
                    as String?;

            if (tempPassword != null && tempPassword.isNotEmpty) {
              await SupabaseService.instance.updatePassword(
                newPassword: tempPassword,
              );
              _logger.i('Password set successfully after OTP verification');
            } else {
              _logger.w(
                'No temp_password found in metadata, using default or skipping password set',
              );
            }
          } catch (passwordError) {
            _logger.e('Failed to set password after OTP: $passwordError');
            // Continue anyway - user can reset password later if needed
          }

          // Create user profile after successful verification
          try {
            await SupabaseService.instance.createUserProfile(
              userId: uid,
              userData: {
                'name': _nameController.text,
                'surname': _surnameController.text,
                'street': _streetController.text,
                'suburb': suburb,
                'city': _selectedCity,
                'province': _selectedProvince,
                'contact': _contactController.text,
                'email': _emailController.text,
                'gender': _selectedGender,
                'ethnicity': _selectedEthnicity,
                'date_of_birth': _selectedDate?.toIso8601String(),
              },
            );
            _logger.i('User profile created successfully');

            // Membership record is now created by the createUserProfile function

            _logger.i('About to trigger payment navigation');

            // Set flag to trigger navigation to payment in build method
            setState(() {
              _shouldNavigateToPayment = true;
            });
          } catch (profileError) {
            _logger.e('Profile creation failed: $profileError');

            // OTP verification already succeeded. If a profile row exists,
            // continue instead of showing a false "verification failed" error.
            try {
              final existingProfile = await SupabaseService.instance.client
                  .from('profiles')
                  .select('id')
                  .eq('id', uid)
                  .maybeSingle();

              if (existingProfile != null) {
                _logger.w(
                  'Profile write failed but profile exists for $uid. Continuing to payment flow.',
                );
                if (mounted) {
                  _scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Account verified. Continuing to payment setup.',
                      ),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
                setState(() {
                  _shouldNavigateToPayment = true;
                });
                return;
              }
            } catch (profileLookupError) {
              _logger.w(
                'Could not confirm profile existence after write failure: $profileLookupError',
              );
            }

            if (mounted) {
              _scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Account verified, but profile setup failed. Please contact support if this persists.',
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 4),
                ),
              );
            }
            return;
          }
        },
        userType: 'member', // Specify this is for member signup
      ),
    );
  }

  void _proceedToPayment() {
    _logger.i(
      'Proceeding to terms acceptance and payment flow after OTP verification',
    );

    final userId = SupabaseService.instance.client.auth.currentUser?.id;
    _logger.i('Current user ID: $userId');

    // Use a very short delay to ensure dialog is fully closed
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) {
        _logger.e(
          'MembersSignupPage context is not mounted after delay, cannot navigate',
        );
        return;
      }

      _logger.i(
        'Context is still mounted after delay, proceeding with navigation',
      );

      // CRITICAL: Use centralized navigation to enforce terms acceptance before payment
      // This ensures member must accept terms & conditions before reaching payment screen
      NavigationService().navigateToHomeAfterAuth(context);
    });
  }

}

class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(title: const Text('Payment Successful')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text(
              'Welcome to Local Lekker!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your subscription has been activated successfully.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // Navigate to appropriate home screen based on user role
                NavigationService().navigateToHomeAfterAuth(context);
              },
              child: const Text('Get Started'),
            ),
          ],
        ),
      ),
    );
  }
}
