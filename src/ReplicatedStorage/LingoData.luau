-- Shared data: languages, interface translations, scenarios and sounds.
-- Used by LingoClient (client) and LingoServer (server).

local Data = {}

---------------------------------------------------------------------
-- Languages: exactly the ones Roblox speech-to-text supports.
-- voice = Roblox text-to-speech voice id; nil means Roblox has no voice for
-- that language, so the NPC's lines are shown as text only.
---------------------------------------------------------------------

Data.Languages = {
	{ code = "en", native = "English", english = "English", voice = "4" },
	{ code = "es", native = "Español", english = "Spanish", voice = "102" },
	{ code = "fr", native = "Français", english = "French", voice = "402" },
	{ code = "de", native = "Deutsch", english = "German", voice = "202" },
	{ code = "it", native = "Italiano", english = "Italian", voice = "302" },
	{ code = "pt", native = "Português", english = "Portuguese", voice = "1002" },
	{ code = "ja", native = "日本語", english = "Japanese", voice = "702" },
	{ code = "ko", native = "한국어", english = "Korean", voice = "902" },
	{ code = "zh-CN", native = "简体中文", english = "Chinese (Simplified)", voice = "502" },
	{ code = "zh-TW", native = "繁體中文", english = "Chinese (Traditional)", voice = "502" },
	{ code = "ar", native = "العربية", english = "Arabic", voice = "802" },
	{ code = "ru", native = "Русский", english = "Russian" },
	{ code = "pl", native = "Polski", english = "Polish" },
	{ code = "tr", native = "Türkçe", english = "Turkish" },
	{ code = "id", native = "Bahasa Indonesia", english = "Indonesian" },
	{ code = "vi", native = "Tiếng Việt", english = "Vietnamese" },
	{ code = "th", native = "ไทย", english = "Thai" },
}

Data.LanguageByCode = {}
for _, language in Data.Languages do
	Data.LanguageByCode[language.code] = language
end

-- A second (male) voice per language, so different NPCs sound different
local MALE_VOICES = {
	["en"] = "3", ["es"] = "101", ["fr"] = "401", ["de"] = "201", ["it"] = "301", ["pt"] = "1001",
	["ja"] = "701", ["ko"] = "901", ["zh-CN"] = "501", ["zh-TW"] = "501", ["ar"] = "801",
}
for code, voice in MALE_VOICES do
	Data.LanguageByCode[code].voiceMale = voice
end

-- A flag for each language, shown beside it in the language list
local FLAGS = {
	["en"] = "\u{1F1EC}\u{1F1E7}", ["es"] = "\u{1F1EA}\u{1F1F8}", ["fr"] = "\u{1F1EB}\u{1F1F7}", ["de"] = "\u{1F1E9}\u{1F1EA}",
	["it"] = "\u{1F1EE}\u{1F1F9}", ["pt"] = "\u{1F1E7}\u{1F1F7}", ["ja"] = "\u{1F1EF}\u{1F1F5}", ["ko"] = "\u{1F1F0}\u{1F1F7}",
	["zh-CN"] = "\u{1F1E8}\u{1F1F3}", ["zh-TW"] = "\u{1F1F9}\u{1F1FC}", ["ar"] = "\u{1F1F8}\u{1F1E6}", ["ru"] = "\u{1F1F7}\u{1F1FA}",
	["pl"] = "\u{1F1F5}\u{1F1F1}", ["tr"] = "\u{1F1F9}\u{1F1F7}", ["id"] = "\u{1F1EE}\u{1F1E9}", ["vi"] = "\u{1F1FB}\u{1F1F3}",
	["th"] = "\u{1F1F9}\u{1F1ED}",
}
for code, flag in FLAGS do
	Data.LanguageByCode[code].flag = flag
end

---------------------------------------------------------------------
-- Interface text, per main language
---------------------------------------------------------------------

local UI_KEYS = {
	"learn", "scenario", "fastfood", "fastfoodDesc", "more", "back", "loading",
	"listening", "thinking", "take", "noVoice", "goCounter", "cooking", "sit",
	"airplane", "airplaneDesc", "dinner", "dinnerDesc",
}

local UI_TEXT = {
	["en"] = { "Which language do you want to practise?", "Choose a scenario", "Fast food", "Order a meal at the counter", "More coming soon", "Back", "Loading…", "Listening… speak now", "Thinking…", "Take your tray", "Text only (no voice)", "Walk up to the counter to order", "Your food is being prepared…", "Sit", "Airplane", "Talk with the cabin crew and passengers", "Dinner", "Eat out at a restaurant with a friend" },
	["es"] = { "¿Qué idioma quieres practicar?", "Elige un escenario", "Comida rápida", "Pide una comida en el mostrador", "Próximamente más", "Atrás", "Cargando…", "Escuchando… habla ahora", "Pensando…", "Toma tu bandeja", "Solo texto (sin voz)", "Acércate al mostrador para pedir", "Están preparando tu comida…", "Sentarse", "Avión", "Habla con la tripulación y los pasajeros", "Cena", "Cena en un restaurante con un amigo" },
	["fr"] = { "Quelle langue veux-tu pratiquer ?", "Choisis un scénario", "Restauration rapide", "Commande un repas au comptoir", "D'autres arrivent bientôt", "Retour", "Chargement…", "J'écoute… parle maintenant", "Réflexion…", "Prends ton plateau", "Texte seulement (sans voix)", "Approche-toi du comptoir pour commander", "Ton repas est en préparation…", "S'asseoir", "Avion", "Parle avec l'équipage et les passagers", "Dîner", "Dîne au restaurant avec un ami" },
	["de"] = { "Welche Sprache möchtest du üben?", "Wähle ein Szenario", "Fast Food", "Bestelle ein Essen an der Theke", "Bald gibt es mehr", "Zurück", "Lädt…", "Ich höre zu… sprich jetzt", "Denkt nach…", "Nimm dein Tablett", "Nur Text (keine Stimme)", "Geh zur Theke, um zu bestellen", "Dein Essen wird zubereitet…", "Hinsetzen", "Flugzeug", "Sprich mit der Crew und den Passagieren", "Abendessen", "Geh mit einem Freund im Restaurant essen" },
	["it"] = { "Quale lingua vuoi praticare?", "Scegli uno scenario", "Fast food", "Ordina un pasto al bancone", "Altri in arrivo", "Indietro", "Caricamento…", "Ti ascolto… parla ora", "Sto pensando…", "Prendi il tuo vassoio", "Solo testo (senza voce)", "Avvicinati al bancone per ordinare", "Stanno preparando il tuo ordine…", "Siediti", "Aereo", "Parla con l'equipaggio e i passeggeri", "Cena", "Cena al ristorante con un amico" },
	["pt"] = { "Que idioma você quer praticar?", "Escolha um cenário", "Fast food", "Peça uma refeição no balcão", "Mais em breve", "Voltar", "Carregando…", "Ouvindo… fale agora", "Pensando…", "Pegue sua bandeja", "Só texto (sem voz)", "Vá até o balcão para pedir", "Sua comida está sendo preparada…", "Sentar", "Avião", "Converse com a tripulação e os passageiros", "Jantar", "Jante em um restaurante com um amigo" },
	["ja"] = { "どの言語を練習しますか？", "シナリオを選んでください", "ファストフード", "カウンターで食事を注文する", "近日追加予定", "戻る", "読み込み中…", "聞いています… 話してください", "考え中…", "トレーを受け取ってください", "テキストのみ（音声なし）", "カウンターまで歩いて注文しましょう", "お料理を準備しています…", "座る", "飛行機", "客室乗務員や乗客と話す", "ディナー", "友だちとレストランで食事する" },
	["ko"] = { "어떤 언어를 연습하고 싶나요?", "시나리오를 선택하세요", "패스트푸드", "카운터에서 음식을 주문하기", "곧 추가됩니다", "뒤로", "불러오는 중…", "듣고 있어요… 지금 말하세요", "생각 중…", "쟁반을 가져가세요", "텍스트만 (음성 없음)", "카운터로 가서 주문하세요", "음식을 준비하고 있어요…", "앉기", "비행기", "승무원과 승객과 대화하기", "저녁 식사", "친구와 레스토랑에서 식사하기" },
	["zh-CN"] = { "你想练习哪种语言？", "选择一个场景", "快餐店", "在柜台点餐", "更多场景即将推出", "返回", "加载中…", "正在听… 请说话", "思考中…", "请取走你的托盘", "仅文字（无语音）", "走到柜台点餐", "正在准备你的餐点…", "坐下", "飞机", "和乘务员、乘客聊天", "晚餐", "和朋友在餐厅吃饭" },
	["zh-TW"] = { "你想練習哪種語言？", "選擇一個情境", "速食店", "在櫃檯點餐", "更多情境即將推出", "返回", "載入中…", "正在聆聽… 請說話", "思考中…", "請取走你的托盤", "僅文字（無語音）", "走到櫃檯點餐", "正在準備你的餐點…", "坐下", "飛機", "和空服員、乘客聊天", "晚餐", "和朋友在餐廳吃飯" },
	["ar"] = { "ما اللغة التي تريد ممارستها؟", "اختر موقفًا", "مطعم وجبات سريعة", "اطلب وجبة من المنضدة", "المزيد قريبًا", "رجوع", "جارٍ التحميل…", "أستمع… تحدث الآن", "أفكر…", "خذ صينيتك", "نص فقط (بدون صوت)", "اذهب إلى المنضدة لتطلب", "يتم تحضير طعامك…", "اجلس", "الطائرة", "تحدث مع الطاقم والركاب", "العشاء", "تناول العشاء في مطعم مع صديق" },
	["ru"] = { "Какой язык вы хотите практиковать?", "Выберите сценарий", "Фастфуд", "Закажите еду у стойки", "Скоро будет больше", "Назад", "Загрузка…", "Слушаю… говорите", "Думаю…", "Возьмите свой поднос", "Только текст (без голоса)", "Подойдите к стойке, чтобы сделать заказ", "Ваш заказ готовится…", "Сесть", "Самолёт", "Поговорите с экипажем и пассажирами", "Ужин", "Поужинайте в ресторане с другом" },
	["pl"] = { "Jaki język chcesz ćwiczyć?", "Wybierz scenariusz", "Fast food", "Zamów posiłek przy ladzie", "Wkrótce więcej", "Wstecz", "Ładowanie…", "Słucham… mów teraz", "Myślę…", "Weź swoją tacę", "Tylko tekst (bez głosu)", "Podejdź do lady, aby zamówić", "Twoje jedzenie jest przygotowywane…", "Usiądź", "Samolot", "Porozmawiaj z załogą i pasażerami", "Kolacja", "Zjedz kolację w restauracji z przyjacielem" },
	["tr"] = { "Hangi dili pratik yapmak istiyorsun?", "Bir senaryo seç", "Fast food", "Tezgâhta yemek sipariş et", "Yakında daha fazlası", "Geri", "Yükleniyor…", "Dinliyorum… şimdi konuş", "Düşünüyor…", "Tepsini al", "Yalnızca metin (ses yok)", "Sipariş vermek için tezgâha yürü", "Yemeğin hazırlanıyor…", "Otur", "Uçak", "Kabin ekibi ve yolcularla konuş", "Akşam yemeği", "Bir arkadaşınla restoranda yemek ye" },
	["id"] = { "Bahasa apa yang ingin kamu latih?", "Pilih skenario", "Makanan cepat saji", "Pesan makanan di konter", "Segera hadir lainnya", "Kembali", "Memuat…", "Mendengarkan… bicaralah sekarang", "Berpikir…", "Ambil nampanmu", "Hanya teks (tanpa suara)", "Jalan ke konter untuk memesan", "Makananmu sedang disiapkan…", "Duduk", "Pesawat", "Bicara dengan awak kabin dan penumpang", "Makan malam", "Makan di restoran bersama teman" },
	["vi"] = { "Bạn muốn luyện ngôn ngữ nào?", "Chọn một tình huống", "Đồ ăn nhanh", "Gọi món tại quầy", "Sắp có thêm", "Quay lại", "Đang tải…", "Đang nghe… hãy nói đi", "Đang suy nghĩ…", "Lấy khay của bạn", "Chỉ có chữ (không có giọng nói)", "Đi tới quầy để gọi món", "Món ăn của bạn đang được chuẩn bị…", "Ngồi", "Máy bay", "Trò chuyện với tiếp viên và hành khách", "Bữa tối", "Ăn tối ở nhà hàng với một người bạn" },
	["th"] = { "คุณอยากฝึกภาษาอะไร", "เลือกสถานการณ์", "ฟาสต์ฟู้ด", "สั่งอาหารที่เคาน์เตอร์", "เร็ว ๆ นี้จะมีเพิ่ม", "ย้อนกลับ", "กำลังโหลด…", "กำลังฟัง… พูดได้เลย", "กำลังคิด…", "หยิบถาดของคุณ", "ข้อความเท่านั้น (ไม่มีเสียง)", "เดินไปที่เคาน์เตอร์เพื่อสั่งอาหาร", "กำลังเตรียมอาหารของคุณ…", "นั่ง", "เครื่องบิน", "พูดคุยกับลูกเรือและผู้โดยสาร", "อาหารค่ำ", "ทานอาหารที่ร้านกับเพื่อน" },
}

-- Data.Text(languageCode, key) -> interface string (falls back to English)
function Data.Text(code, key)
	local index = table.find(UI_KEYS, key)
	local row = UI_TEXT[code] or UI_TEXT["en"]
	return (index and row[index]) or (index and UI_TEXT["en"][index]) or key
end

---------------------------------------------------------------------
-- Fast food scenario
---------------------------------------------------------------------

local MENU_ORDER = { "burger", "turkey", "taco", "cola", "milk" }

local MENU_NAMES = {
	["en"] = { "Cheezburger", "Turkey Leg", "Taco", "Bloxy Cola", "Chocolate Milk" },
	["es"] = { "Hamburguesa con queso", "Muslo de pavo", "Taco", "Bloxy Cola", "Leche con chocolate" },
	["fr"] = { "Cheeseburger", "Cuisse de dinde", "Taco", "Bloxy Cola", "Lait au chocolat" },
	["de"] = { "Cheeseburger", "Truthahnkeule", "Taco", "Bloxy Cola", "Schokomilch" },
	["it"] = { "Cheeseburger", "Coscia di tacchino", "Taco", "Bloxy Cola", "Latte al cioccolato" },
	["pt"] = { "Cheeseburger", "Coxa de peru", "Taco", "Bloxy Cola", "Leite com chocolate" },
	["ja"] = { "チーズバーガー", "ターキーレッグ", "タコス", "Bloxy Cola", "チョコレートミルク" },
	["ko"] = { "치즈버거", "칠면조 다리", "타코", "Bloxy Cola", "초코우유" },
	["zh-CN"] = { "芝士汉堡", "火鸡腿", "塔可", "Bloxy Cola", "巧克力牛奶" },
	["zh-TW"] = { "起司漢堡", "火雞腿", "塔可", "Bloxy Cola", "巧克力牛奶" },
	["ar"] = { "تشيز برجر", "فخذ ديك رومي", "تاكو", "Bloxy Cola", "حليب بالشوكولاتة" },
	["ru"] = { "Чизбургер", "Ножка индейки", "Тако", "Bloxy Cola", "Шоколадное молоко" },
	["pl"] = { "Cheeseburger", "Udko z indyka", "Taco", "Bloxy Cola", "Mleko czekoladowe" },
	["tr"] = { "Çizburger", "Hindi budu", "Tako", "Bloxy Cola", "Çikolatalı süt" },
	["id"] = { "Burger keju", "Paha kalkun", "Taco", "Bloxy Cola", "Susu cokelat" },
	["vi"] = { "Bánh mì kẹp phô mai", "Đùi gà tây", "Taco", "Bloxy Cola", "Sữa sô cô la" },
	["th"] = { "ชีสเบอร์เกอร์", "น่องไก่งวง", "ทาโก้", "Bloxy Cola", "นมช็อกโกแลต" },
}

Data.FastFood = {
	RestaurantName = "Bloxy Burger",
	CashierName = "Sam",
	CookName = "Rico",
	CleanerName = "Mia",
	CustomerName = "Leo",
	MaxItemsPerOrder = 6,

	-- station = which kitchen station the cook uses; seconds = how long it takes
	-- The food is official Roblox gear: real Tools (templates in ReplicatedStorage.FoodTools, same ids).
	-- station = which kitchen station the cook uses; seconds = how long it takes;
	-- bites = how many bites or sips it lasts; fill = how much each one fills the stomach (1 = full)
	Menu = {
		{ id = "burger", price = 5, station = "Grill", seconds = 2.6, kind = "food", bites = 4, fill = 0.12 },
		{ id = "turkey", price = 6, station = "Oven", seconds = 2.8, kind = "food", bites = 5, fill = 0.12 },
		{ id = "taco", price = 4, station = "Fryer", seconds = 2.2, kind = "food", bites = 3, fill = 0.11 },
		{ id = "cola", price = 2, station = "Drinks", seconds = 1.8, kind = "drink", bites = 4, fill = 0.06 },
		{ id = "milk", price = 3, station = "Freezer", seconds = 1.8, kind = "drink", bites = 4, fill = 0.07 },
	},

	-- Where things are in the building (world coordinates)
	-- Where things are in the building (world coordinates). The building is the
	-- McDonald's-style build; the earlier one is saved in ServerStorage.Archive_OldScenes.
	Layout = {
		Center = Vector3.new(0, 0, -52),
		DoorZ = -29.8, -- the entrance; inside the building is anything with a smaller Z than this
		TutorSpot = Vector3.new(6, 5.5, -11), -- where Lumi the guide floats, outside the entrance
		-- dining room: where the regular customer hangs around, and the tables people can sit at
		CustomerSpots = { Vector3.new(-27.5, 0, -35), Vector3.new(-27.5, 0, -42.5), Vector3.new(-27.5, 0, -50) }, -- along the left wall, away from the counter
		AisleX = 27.5, -- side aisles run along x = -27.5 and x = 27.5
		FrontZ = -53.5, -- clear strip between the booths and the counter
		BenchOffsetZ = 2.8, -- benches sit this far either side of a table's centre
		BenchTopY = 2.1,
		SeatedRootY = 3.1, -- height of an NPC's root part when sitting on a bench
		CounterFront = Vector3.new(0, 0, -57), -- where the customer stands (the ORDER HERE mat)
		Pickup = Vector3.new(8, 3.36, -61.6), -- tray spot on the counter
		CookPickupStand = Vector3.new(8, 0, -64.8),
		RegisterDrawer = Vector3.new(2.4, 3.45, -63.4), -- the drawer slides out from here toward the cashier
		CashierRetreats = { Vector3.new(-20, 0, -66.5), Vector3.new(20, 0, -66.5) }, -- where she goes if told to go away
		KitchenLaneZ = -69, -- the cook walks along this line
		StationX = { Grill = -24, Fryer = 14, Oven = 5, Drinks = -14, Freezer = 27.5 },
		-- height of each station's working surface
		StationTopY = { Grill = 3.6, Fryer = 4.55, Oven = 4.7, Drinks = 3.95, Freezer = 5.0 },
		StationZ = -72.7,
		CleanerPath = { Vector3.new(28, 0, -34), Vector3.new(28, 0, -51), Vector3.new(26.8, 0, -52.5), Vector3.new(28, 0, -42) },
	},
}

Data.FastFood.MenuById = {}
for _, item in Data.FastFood.Menu do
	Data.FastFood.MenuById[item.id] = item
end

-- Data.FastFood.ItemName(languageCode, itemId) -> name of a menu item
function Data.FastFood.ItemName(code, itemId)
	local index = table.find(MENU_ORDER, itemId)
	local row = MENU_NAMES[code] or MENU_NAMES["en"]
	return (index and row[index]) or itemId
end

---------------------------------------------------------------------
-- Airplane and dinner scenarios (run by ReplicatedStorage.LingoScenes)
---------------------------------------------------------------------

-- Every dish and drink is official Roblox gear (the Tools in ReplicatedStorage.FoodTools,
-- which have the same ids), so the menus only offer what exists as gear.
local DINNER_ORDER = { "pizza", "turkey", "doubleburger", "watermelon", "cake", "cola" }

local DINNER_NAMES = {
	["en"] = { "Pepperoni pizza", "Roast turkey leg", "Double cheeseburger", "Watermelon", "Chocolate cake", "Cola" },
	["es"] = { "Pizza de pepperoni", "Muslo de pavo asado", "Hamburguesa doble con queso", "Sandía", "Tarta de chocolate", "Refresco de cola" },
	["fr"] = { "Pizza au pepperoni", "Cuisse de dinde rôtie", "Double cheeseburger", "Pastèque", "Gâteau au chocolat", "Cola" },
	["de"] = { "Salamipizza", "Gebratene Putenkeule", "Doppelter Cheeseburger", "Wassermelone", "Schokoladenkuchen", "Cola" },
	["it"] = { "Pizza al salame piccante", "Coscia di tacchino arrosto", "Doppio cheeseburger", "Anguria", "Torta al cioccolato", "Cola" },
	["pt"] = { "Pizza de pepperoni", "Coxa de peru assada", "Cheeseburger duplo", "Melancia", "Bolo de chocolate", "Refrigerante de cola" },
	["ja"] = { "ペパロニピザ", "ローストターキーレッグ", "ダブルチーズバーガー", "スイカ", "チョコレートケーキ", "コーラ" },
	["ko"] = { "페퍼로니 피자", "칠면조 다리 구이", "더블 치즈버거", "수박", "초콜릿 케이크", "콜라" },
	["zh-CN"] = { "意式辣香肠披萨", "烤火鸡腿", "双层芝士汉堡", "西瓜", "巧克力蛋糕", "可乐" },
	["zh-TW"] = { "義式臘腸披薩", "烤火雞腿", "雙層起司漢堡", "西瓜", "巧克力蛋糕", "可樂" },
	["ar"] = { "بيتزا ببروني", "فخذ ديك رومي مشوي", "برجر مزدوج بالجبن", "بطيخ", "كعكة شوكولاتة", "كولا" },
	["ru"] = { "Пицца пепперони", "Жареная ножка индейки", "Двойной чизбургер", "Арбуз", "Шоколадный торт", "Кола" },
	["pl"] = { "Pizza pepperoni", "Pieczone udko z indyka", "Podwójny cheeseburger", "Arbuz", "Ciasto czekoladowe", "Cola" },
	["tr"] = { "Pepperonili pizza", "Kızarmış hindi budu", "Duble çizburger", "Karpuz", "Çikolatalı pasta", "Kola" },
	["id"] = { "Piza pepperoni", "Paha kalkun panggang", "Burger keju dobel", "Semangka", "Kue cokelat", "Kola" },
	["vi"] = { "Pizza pepperoni", "Đùi gà tây nướng", "Bánh mì kẹp phô mai hai tầng", "Dưa hấu", "Bánh sô cô la", "Cô ca" },
	["th"] = { "พิซซ่าเปปเปอโรนี", "น่องไก่งวงอบ", "ดับเบิลชีสเบอร์เกอร์", "แตงโม", "เค้กช็อกโกแลต", "โคล่า" },
}

local AIRPLANE_ORDER = { "cola", "milk", "coffee", "cocoa", "sandwich", "cookie" }

local AIRPLANE_NAMES = {
	["en"] = { "Cola", "Chocolate milk", "Coffee", "Hot chocolate", "Sandwich", "Fortune cookie" },
	["es"] = { "Refresco de cola", "Leche con chocolate", "Café", "Chocolate caliente", "Sándwich", "Galleta de la fortuna" },
	["fr"] = { "Cola", "Lait au chocolat", "Café", "Chocolat chaud", "Sandwich", "Biscuit chinois" },
	["de"] = { "Cola", "Schokomilch", "Kaffee", "Heiße Schokolade", "Sandwich", "Glückskeks" },
	["it"] = { "Cola", "Latte al cioccolato", "Caffè", "Cioccolata calda", "Panino", "Biscotto della fortuna" },
	["pt"] = { "Refrigerante de cola", "Leite com chocolate", "Café", "Chocolate quente", "Sanduíche", "Biscoito da sorte" },
	["ja"] = { "コーラ", "チョコレートミルク", "コーヒー", "ホットチョコレート", "サンドイッチ", "フォーチュンクッキー" },
	["ko"] = { "콜라", "초코우유", "커피", "핫초코", "샌드위치", "포춘 쿠키" },
	["zh-CN"] = { "可乐", "巧克力牛奶", "咖啡", "热巧克力", "三明治", "幸运饼干" },
	["zh-TW"] = { "可樂", "巧克力牛奶", "咖啡", "熱巧克力", "三明治", "幸運餅乾" },
	["ar"] = { "كولا", "حليب بالشوكولاتة", "قهوة", "شوكولاتة ساخنة", "شطيرة", "كعكة الحظ" },
	["ru"] = { "Кола", "Шоколадное молоко", "Кофе", "Горячий шоколад", "Сэндвич", "Печенье с предсказанием" },
	["pl"] = { "Cola", "Mleko czekoladowe", "Kawa", "Gorąca czekolada", "Kanapka", "Ciasteczko z wróżbą" },
	["tr"] = { "Kola", "Çikolatalı süt", "Kahve", "Sıcak çikolata", "Sandviç", "Fal kurabiyesi" },
	["id"] = { "Kola", "Susu cokelat", "Kopi", "Cokelat panas", "Roti lapis", "Kue keberuntungan" },
	["vi"] = { "Cô ca", "Sữa sô cô la", "Cà phê", "Sô cô la nóng", "Bánh mì kẹp", "Bánh quy may mắn" },
	["th"] = { "โคล่า", "นมช็อกโกแลต", "กาแฟ", "ช็อกโกแลตร้อน", "แซนด์วิช", "คุกกี้เสี่ยงทาย" },
}

Data.Scenes = {
	-- A flight: the cabin sits high in the sky and clouds stream past the windows
	airplane = {
		AirlineName = "Bloxy Air",
		AttendantName = "Nora",
		PassengerAName = "Iris", -- across the aisle
		PassengerBName = "Hugo", -- in the window seat beside the player
		MaxItems = 3,
		-- what the flight attendant can bring, free of charge
		Items = {
			{ id = "cola", english = "Cola" },
			{ id = "milk", english = "Chocolate milk" },
			{ id = "coffee", english = "Coffee" },
			{ id = "cocoa", english = "Hot chocolate" },
			{ id = "sandwich", english = "Sandwich" },
			{ id = "cookie", english = "Fortune cookie" },
		},
		Layout = {
			FloorY = 200,
			Spawn = Vector3.new(0, 204, 14), -- where the player starts: in the aisle, far enough from the rear wall that a camera behind them is still inside the cabin
			PlayerSeat = Vector3.new(6, 202, 4), -- top of the seat cushion
			SeatedRootY = 203, -- height of an NPC's root part when sitting in a seat
			PassengerASeat = Vector3.new(-6, 0, 4),
			PassengerBSeat = Vector3.new(9.5, 0, 4),
			AttendantStand = Vector3.new(1.2, 0, -1), -- in the aisle, ahead of the player's row, so they need not turn their head far
			Galley = Vector3.new(0, 0, 28),
			TrayTable = Vector3.new(6, 203.48, -0.4), -- top of the fold-down table
			TutorSpot = Vector3.new(-2.6, 205.5, 8), -- beside the aisle, ahead of where the player starts
		},
	},

	-- Dinner out with a friend
	dinner = {
		RestaurantName = "La Luna",
		WaitressName = "Clara",
		FriendName = "Alex",
		MaxItems = 6,
		Items = {
			{ id = "pizza", price = 12 }, { id = "turkey", price = 18 }, { id = "doubleburger", price = 14 },
			{ id = "watermelon", price = 5 }, { id = "cake", price = 6 }, { id = "cola", price = 3 },
		},
		Layout = {
			DoorZ = -25, -- inside the restaurant is anything with a smaller Z than this
			HostSpot = Vector3.new(5, 0, -32), -- where the waitress waits by the door
			MainTable = Vector3.new(-10, 0, -45),
			TableTopY = 3.32, -- top of the tablecloth
			TableStand = Vector3.new(-5.2, 0, -45), -- where the waitress stands at the table
			BenchOffsetZ = 3,
			BenchTopY = 2.1,
			SeatedRootY = 3.1,
			ToTable = { Vector3.new(0, 0, -36), Vector3.new(-5.2, 0, -45) },
			ToKitchen = { Vector3.new(0, 0, -50), Vector3.new(0, 0, -61.8), Vector3.new(13, 0, -61.8) },
			TutorSpot = Vector3.new(7, 5.5, -12),
		},
	},
}

for _, scene in Data.Scenes do
	scene.ItemById = {}
	for _, item in scene.Items do
		scene.ItemById[item.id] = item
	end
end

-- Name of something served on the plane in a language
function Data.Scenes.airplane.ItemName(code, itemId)
	local index = table.find(AIRPLANE_ORDER, itemId)
	local row = AIRPLANE_NAMES[code] or AIRPLANE_NAMES["en"]
	return (index and row[index]) or itemId
end

-- Name of a dinner dish in a language
function Data.Scenes.dinner.ItemName(code, itemId)
	local index = table.find(DINNER_ORDER, itemId)
	local row = DINNER_NAMES[code] or DINNER_NAMES["en"]
	return (index and row[index]) or itemId
end

---------------------------------------------------------------------
-- Sounds (free Roblox library audio)
---------------------------------------------------------------------

Data.Sounds = {
	Music = { id = "rbxassetid://1835966301", volume = 0.35, looped = true }, -- APM Music: Hello Montmartre
	Crowd = { id = "rbxassetid://9113662272", volume = 0.12, looped = true }, -- cafe crowd ambience
	Sizzle = { id = "rbxassetid://9114542867", volume = 0.5, looped = true },
	Click = { id = "rbxassetid://9119717523", volume = 0.6 },
	Whoosh = { id = "rbxassetid://9126283592", volume = 0.5 },
	Appear = { id = "rbxassetid://9125959352", volume = 0.7 },
	Register = { id = "rbxassetid://9113728042", volume = 0.6 },
	Bell = { id = "rbxassetid://9125485591", volume = 0.7 },
	Cabin = { id = "rbxassetid://1330849332", volume = 0.22, looped = true }, -- steady hum for the plane
}

-- The floating guide outside every scenario
Data.TutorName = "Lumi"

return Data
