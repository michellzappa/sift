# The made-up sample data for demo mode: one fictional person's links.
#
# Every name, handle and site below is invented. Sites use the reserved
# .example top-level domain (RFC 2606). Wikipedia articles are real public
# pages. X and Instagram handles start with "demo" and YouTube ids with
# "siftdemo", so none of them can be taken for a real account or video.
#
# A link is (source, site, title, preview):
#   I = Safari on the iPhone, M = Safari on the Studio Mac, R = Reading List,
#   G = Instagram Saved (site = account), X = X Bookmarks (site = handle,
#   title = the post), Y = YouTube Watch Later (site = channel name).
#   A site "wiki:Article" is the English Wikipedia article.

THEMES = [
    {
        "name": "Home Robotics",
        "summary": "Small robots for the flat and the workshop: arms, vacuums, plant waterers, and the motors and sensors that make them work.",
        "glyph": "R",
        "links": [
            ("I", "wiki:Robot_Operating_System", "Robot Operating System", "The open middleware most hobby robots end up running, with drivers and tools for sensors and motors."),
            ("I", "tinybots.example", "Building a two-wheel balancing robot from a kit", "Parts list, a PID tuning walkthrough, and the wobble you get before it settles."),
            ("R", "workshopnotes.example", "Why my robot vacuum keeps getting stuck under the sofa", "A teardown of the bump sensor and a fix with a 3D printed skirt."),
            ("Y", "Bench Robotics Lab", "Servo or stepper for a robot arm?", "Side by side tests on a cheap arm, with a kitchen scale to measure torque."),
            ("Y", "Bench Robotics Lab", "Lidar on a budget, tested in a small flat", "Three sensors under 100 euros mapping the same two rooms."),
            ("X", "demo_botbench", "Got the arm to pick up a mug without crushing it. Force sensing resistors under the gripper pads did it.", ""),
            ("G", "demo.makerspace", "Demo Makerspace", "Saturday build night: line followers racing on a taped track."),
            ("I", "wiki:Roomba", "Roomba", "History of the robot vacuum, from the first model in 2002 to mapping and docking."),
            ("M", "tinybots.example", "Choosing a motor driver for small DC motors", "H-bridges compared by current, heat, and how easy they are to wire."),
            ("R", "homelab.example", "A robot that waters the plants while I'm away", "Soil sensors, a peristaltic pump and a schedule that checks the weather first."),
            ("I", "robotics.example.org", "Open source robot arms worth building", "Six designs with printed parts, what each one costs, and how precise they get."),
            ("X", "demo_botbench", "The hardest part of home robots is not the robot. It's the cables on the floor.", ""),
            ("M", "wiki:Simultaneous_localization_and_mapping", "Simultaneous localization and mapping", "How a robot builds a map of a room while working out where it is on that map."),
            ("Y", "Tiny Machines", "I let a robot fold my laundry for a week", "It folded 41 shirts. Socks beat it every time."),
            ("G", "demo.robot.garden", "Robot Garden Club", "Seed planter, version three. Fewer jams, still slow."),
        ],
    },
    {
        "name": "Fermentation and Food Science",
        "summary": "Koji, kimchi, sourdough and hot sauce, plus the chemistry that explains why they work and how they go wrong.",
        "glyph": "F",
        "links": [
            ("I", "wiki:Lactic_acid_fermentation", "Lactic acid fermentation", "The chemistry behind sauerkraut, kimchi and sour beer, on one page."),
            ("R", "saltandtime.example", "A beginner's guide to koji at home", "Growing koji on rice in a cooler box with a heating pad and a cheap thermometer."),
            ("G", "demo.ferment.club", "Ferment Club", "Week two of the hot sauce mash. The color went from red to almost brown."),
            ("Y", "Crock and Jar", "Why your sauerkraut went soft, and how to stop it", "Salt, temperature and the one mistake that turns cabbage to mush."),
            ("I", "wiki:Kimchi", "Kimchi", "Korean fermented vegetables, with the regional styles and how long each one keeps."),
            ("X", "demo_sourcrock", "Salt by weight, not by the spoonful. 2% of the cabbage weight. It changed everything for me.", ""),
            ("R", "foodlab.example", "What the Maillard reaction is, and why browning tastes good", "Sugars, amino acids and heat, with photos of the same steak at five temperatures."),
            ("I", "wiki:Aspergillus_oryzae", "Aspergillus oryzae", "The mould behind miso, soy sauce and sake."),
            ("M", "saltandtime.example", "Garum from chicken wings, a six week project", "A Roman fish sauce method that works with leftovers from the freezer."),
            ("G", "demo.ferment.club", "Ferment Club", "Kombucha scoby hotel, now on shelf two."),
            ("R", "foodlab.example", "Measuring pH at home without lab gear", "Test strips against a pocket meter, checked with lemon juice and vinegar."),
            ("Y", "Crock and Jar", "Miso in 90 days, start to finish", "Soybeans, koji and salt in a crock, opened once a month on camera."),
            ("I", "wiki:Sourdough", "Sourdough", "Wild yeast and lactic acid bacteria, and how a starter keeps them in balance."),
            ("X", "demo_sourcrock", "Rye starter fed 1:5:5 doubles in four hours at 26 C. Wheat takes six.", ""),
            ("R", "kitchenscience.example", "The case for weighing everything in the kitchen", "Cups lie. A scale costs less than a bag of good flour."),
        ],
    },
    {
        "name": "Urban Cycling",
        "summary": "Getting around the city by bike: protected lanes, cargo bikes, repairs at home and the numbers that convince a city council.",
        "glyph": "C",
        "links": [
            ("I", "wiki:Segregated_cycle_facilities", "Segregated cycle facilities", "Kerbs, bollards and planters: the ways cities separate bikes from cars."),
            ("R", "streetsmag.example", "How one city doubled bike trips in five years", "A council that built a connected network first and argued about it later."),
            ("I", "slowcycle.example", "Cargo bikes that carry two kids", "Seven long-tails and box bikes, loaded and ridden up the same hill."),
            ("G", "demo.citycycles", "City Cycles", "Morning commute along the canal. 14 minutes, no cars."),
            ("Y", "Two Wheels City", "Riding every protected lane in one day", "62 kilometres, three flat tyres, one very good bakery."),
            ("X", "demo_bikelanes", "Counted 312 bikes at the bridge between 8 and 9 this morning. Last spring it was 190.", ""),
            ("M", "slowcycle.example", "Winter tyres for city bikes, tested on ice", "Studded against unstudded on a frozen car park."),
            ("R", "streetsmag.example", "Low traffic neighbourhoods, two years on", "Traffic counts, shop takings and what residents say now."),
            ("I", "wiki:Utility_cycling", "Utility cycling", "Cycling to get somewhere: commuting, shopping and deliveries."),
            ("G", "demo.citycycles", "City Cycles", "The new parking at the station holds 2,000 bikes. It was full by nine."),
            ("I", "slowcycle.example", "Servicing a hub gear at home", "Oil, a cone spanner and an hour on a Sunday."),
            ("Y", "Two Wheels City", "What makes a junction feel safe on a bike", "Sight lines, corner islands and the signal timing nobody notices."),
            ("X", "demo_bikelanes", "Painted lanes are a start. Kerbs are infrastructure.", ""),
            ("R", "mobilitylab.example", "E-bikes and the hills problem: data from 40,000 rides", "Where people stop riding, and how a motor changes the map."),
            ("I", "wiki:Bicycle-sharing_system", "Bicycle-sharing system", "Docked and dockless schemes, from the first white bikes to today's apps."),
        ],
    },
    {
        "name": "Climate Tech",
        "summary": "Heat pumps, batteries, solar and carbon removal, read with an eye on what is cheap and working now.",
        "glyph": "E",
        "links": [
            ("I", "wiki:Heat_pump", "Heat pump", "How a heat pump moves heat instead of making it, and why that triples the efficiency."),
            ("R", "gridnotes.example", "Why batteries now undercut gas peaker plants", "Four years of auction prices on one chart."),
            ("I", "wiki:Direct_air_capture", "Direct air capture", "Pulling carbon dioxide out of ambient air, and what it costs per tonne."),
            ("Y", "Energy Explained", "How a sand battery stores heat for months", "A silo of sand, resistive heaters and a district heating network."),
            ("X", "demo_gridwatch", "Solar covered 61% of demand at noon today. A year ago the record was 48%.", ""),
            ("M", "gridnotes.example", "Reading the grid: a guide to live electricity maps", "What the colors mean, and why the price goes negative on sunny Sundays."),
            ("R", "climatedesk.example", "Green steel without the jargon", "Hydrogen, electric arc furnaces and where the iron ore goes."),
            ("I", "wiki:Grid_energy_storage", "Grid energy storage", "Pumped hydro, batteries, compressed air and flywheels compared."),
            ("G", "demo.solar.rooftop", "Rooftop Solar Diary", "Panels up. Twelve of them, facing south-west, 4.8 kW."),
            ("R", "climatedesk.example", "The heat pump installer shortage, in numbers", "Training places, waiting lists and what it takes to retrain a gas engineer."),
            ("Y", "Energy Explained", "Geothermal anywhere? Drilling deeper with plasma", "A startup's test rig, and the rock that keeps breaking drill bits."),
            ("X", "demo_gridwatch", "Our heat pump used 2,900 kWh last winter. The old boiler burned the equivalent of 11,000.", ""),
            ("I", "wiki:Perovskite_solar_cell", "Perovskite solar cell", "A cheaper crystal for solar panels, and the stability problem it still has."),
            ("M", "climatedesk.example", "Carbon removal startups, and what they remove", "Tonnes delivered against tonnes promised, for twelve companies."),
            ("R", "gridnotes.example", "Balcony solar: what 800 watts gets you", "A year of readings from two panels on a railing."),
        ],
    },
    {
        "name": "Typography and Type Design",
        "summary": "How letters are drawn, spaced and licensed: variable fonts, wood type, signs on the street and the rules for figures in tables.",
        "glyph": "T",
        "links": [
            ("I", "wiki:Helvetica", "Helvetica", "The 1957 Swiss typeface and how it ended up on every subway sign."),
            ("R", "typejournal.example", "Designing a variable font: notes from my first year", "Masters, axes and the interpolation bugs that only show at weight 512."),
            ("G", "demo.letterforms", "Letterforms Studio", "Sketches for a lowercase g. Version 14."),
            ("Y", "Glyph Workshop", "Kerning by eye: a 20 minute exercise", "Space a word upside down and the gaps jump out."),
            ("X", "demo_typenerd", "Optical sizes are the most underused feature in variable fonts. Small text needs looser spacing.", ""),
            ("I", "wiki:OpenType", "OpenType", "The font format behind ligatures, small caps and variable axes."),
            ("M", "typejournal.example", "Licensing fonts for apps without surprises", "Desktop, web and app licences, and the clause about embedding."),
            ("R", "letterpress.example", "Setting a poster in wood type", "A weekend at a print shop, with ink on everything."),
            ("I", "wiki:Typeface", "Typeface", "Typeface, font and family: the words, and the history behind them."),
            ("G", "demo.letterforms", "Letterforms Studio", "Found this hand-painted shop sign. The R is perfect."),
            ("R", "typejournal.example", "Why the same font looks different on Mac and Windows", "Hinting, gamma and the rendering choices each system makes."),
            ("Y", "Glyph Workshop", "Drawing your first typeface in a free editor", "From five letters to a whole alphabet, one evening at a time."),
            ("I", "wiki:Johnston_(typeface)", "Johnston (typeface)", "The 1916 sans serif drawn for the London Underground."),
            ("X", "demo_typenerd", "Tabular figures in tables. Proportional figures in text. That's the whole rule.", ""),
            ("M", "fontspecimens.example", "Specimen: a humanist sans for long reading", "Twelve weights, set at the sizes people really read."),
        ],
    },
    {
        "name": "Deep Sea Biology",
        "summary": "Animals that live in the dark: vents, seeps, whale falls and the robots that film them.",
        "glyph": "D",
        "links": [
            ("I", "wiki:Hydrothermal_vent", "Hydrothermal vent", "Hot springs on the seafloor and the food webs that run on chemistry instead of sunlight."),
            ("R", "oceanlog.example", "What lives at 4,000 metres, by depth zone", "A chart of the animals found at each depth, and how few of them anyone has seen alive."),
            ("Y", "Abyss Notes", "Three hours at a cold seep, filmed by a remote vehicle", "Mussel beds, tube worms and a very curious octopus."),
            ("I", "wiki:Bioluminescence", "Bioluminescence", "Living light: how animals make it and what they use it for."),
            ("G", "demo.deep.blue", "Deep Blue Drawings", "Gulper eel drawing. Mostly mouth."),
            ("X", "demo_abyssal", "The mean depth of the ocean is about 3,700 m. Most of the living space on the planet is dark.", ""),
            ("R", "oceanlog.example", "How scientists keep deep sea animals alive at the surface", "Pressure chambers, cold rooms and a lot of patience."),
            ("I", "wiki:Anglerfish", "Anglerfish", "The fish with a glowing lure, and the strange way the males attach to females."),
            ("M", "seafloor.example", "Deep sea mining: what we know about the sediment plumes", "Test runs, sensor data and the gaps in the data."),
            ("Y", "Abyss Notes", "Whale fall: one skeleton feeds the seafloor for decades", "Time-lapse from a carcass placed at 1,000 metres."),
            ("I", "wiki:Mariana_Trench", "Mariana Trench", "The deepest known point in the ocean, and the few dives that reached the bottom."),
            ("R", "marinebio.example", "Giant isopods, and why they get so big", "Cold water, slow lives and the theory of deep sea gigantism."),
            ("G", "demo.deep.blue", "Deep Blue Drawings", "Siphonophore, painted from a photo. It's a colony, not one animal."),
            ("X", "demo_abyssal", "New species described from last month's dive: two sea cucumbers and a worm with gold scales.", ""),
            ("I", "wiki:Vampire_squid", "Vampire squid", "A deep sea cephalopod that eats marine snow and glows when threatened."),
        ],
    },
    {
        "name": "Personal Knowledge Tools",
        "summary": "Notes, reading logs and flashcards: plain text setups that still open in ten years.",
        "glyph": "N",
        "links": [
            ("I", "wiki:Zettelkasten", "Zettelkasten", "The slip box method: short notes, numbered and linked by hand."),
            ("R", "notesdaily.example", "I tried five note apps in a year. This is what stuck.", "Plain text won, and the search box did most of the work."),
            ("I", "wiki:Memex", "Memex", "Vannevar Bush's 1945 idea for a desk that stores and links everything you read."),
            ("Y", "Second Desk", "My plain text notes setup", "Folders, file names and the one shortcut used fifty times a day."),
            ("X", "demo_plaintext", "Rule I keep: a note should make sense to someone who never saw the source.", ""),
            ("M", "notesdaily.example", "Daily notes or topic notes?", "Two years of each, and why the answer is both."),
            ("R", "knowledgecraft.example", "Spaced repetition for adults who hated flashcards", "Ten cards a day, written in your own words."),
            ("I", "wiki:Spaced_repetition", "Spaced repetition", "Reviewing at growing intervals so things stay in memory."),
            ("G", "demo.deskstudio", "Desk Studio", "Desk reset. Index cards on the left, laptop on the right."),
            ("R", "knowledgecraft.example", "Rereading your notes matters more than linking them", "A month-end review that takes twenty minutes."),
            ("Y", "Second Desk", "Search beats folders: finding old notes fast", "Full text search, dates in file names and nothing else."),
            ("I", "wiki:Commonplace_book", "Commonplace book", "Centuries-old notebooks of quotes and ideas, kept by readers and writers."),
            ("X", "demo_plaintext", "Exported nine years of notes to Markdown this weekend. 4,112 files, all still open in a text editor.", ""),
            ("M", "localfirst.example", "Local-first software in plain terms", "Your files on your machine, sync as an extra."),
            ("R", "notesdaily.example", "How to keep a reading log you use", "Three lines per book: what it said, what I think, what I will do."),
        ],
    },
    {
        "name": "Synthesizers and Sound",
        "summary": "Modular synths, field recordings and the basics of shaping sound, mostly with cheap gear in a small room.",
        "glyph": "S",
        "links": [
            ("I", "wiki:Moog_synthesizer", "Moog synthesizer", "The modular instrument Robert Moog built in the 1960s, and the sound it gave pop music."),
            ("R", "patchnotes.example", "Subtractive synthesis on one page", "Oscillator, filter, amplifier, envelope, in that order."),
            ("Y", "Patch Cable Club", "A drum voice from two oscillators", "Kick, snare and a hi-hat, patched live."),
            ("I", "wiki:Eurorack", "Eurorack", "The modular synth format with 3U rails and 3.5 mm cables."),
            ("G", "demo.modular.room", "Modular Room", "Small case, big mess. Patch of the week."),
            ("X", "demo_patchbay", "Filter first, then the envelope, then the VCA. Every patch I like follows that order.", ""),
            ("M", "patchnotes.example", "A field guide to filter types", "Low-pass, high-pass, band-pass and notch, with audio examples."),
            ("R", "soundlab.example", "Recording room tone in a small flat", "Why every recording needs thirty seconds of silence."),
            ("I", "wiki:Theremin", "Theremin", "The instrument you play without touching it."),
            ("Y", "Patch Cable Club", "Ten minutes with a granular synth and a kettle recording", "One field recording, stretched into a whole track."),
            ("R", "synthdiy.example", "Building a synth kit: what the instructions skip", "Solder order, a cheap multimeter and patience with the trimmers."),
            ("G", "demo.modular.room", "Modular Room", "Sequencer running a Euclidean rhythm, 5 hits in 13 steps."),
            ("I", "wiki:Modular_synthesizer", "Modular synthesizer", "Separate modules joined with patch cables, from the 1960s to now."),
            ("X", "demo_patchbay", "Field recording from the tram stop this morning. The brakes make a perfect drone.", ""),
            ("M", "soundlab.example", "Cheap contact microphones and what they hear", "Piezo discs taped to a fence, a sink and a bike wheel."),
        ],
    },
    {
        "name": "Architecture and Housing",
        "summary": "How cities house people well: timber buildings, cooperatives, retrofits and the plain apartment block.",
        "glyph": "A",
        "links": [
            ("I", "wiki:Passive_house", "Passive house", "A building standard with thick insulation, airtight walls and very low heating needs."),
            ("R", "housingdesk.example", "How Vienna keeps rents low", "A century of city-built housing, and who gets to live there."),
            ("I", "wiki:Cross-laminated_timber", "Cross-laminated timber", "Wood panels glued in layers, strong enough for ten-storey buildings."),
            ("Y", "Building Stories", "A tour of a ten-storey timber apartment block", "Exposed ceilings, a concrete core and the fire tests behind them."),
            ("G", "demo.small.houses", "Small Houses", "Courtyard homes, eight units on a single plot."),
            ("X", "demo_buildbetter", "Shops on the ground floor, four storeys of flats above. The most boring building type, and the one cities need most.", ""),
            ("M", "housingdesk.example", "Missing middle housing, with drawings", "Duplexes, row houses and small blocks that fit on ordinary streets."),
            ("R", "archreview.example", "Retrofitting a 1960s block to near zero energy", "New facade panels went on while people still lived inside."),
            ("I", "wiki:Brutalist_architecture", "Brutalist architecture", "Raw concrete buildings from the 1950s to the 1970s."),
            ("G", "demo.small.houses", "Small Houses", "Sketch of a stair core shared by four flats."),
            ("R", "archreview.example", "Courtyards and light wells in deep plan buildings", "How old city blocks get daylight to every room."),
            ("Y", "Building Stories", "Why old apartments have such thick walls", "Brick, heat and the rules that came after the fires."),
            ("I", "wiki:Cohousing", "Cohousing", "Private homes around shared kitchens, gardens and workshops."),
            ("X", "demo_buildbetter", "Our building's heating bill fell by 70% after the facade insulation. Same boiler.", ""),
            ("M", "housingdesk.example", "Building cooperatives: when residents own the block", "Shares, waiting lists and the meetings nobody misses."),
        ],
    },
]

# Links outside the themes. Errands are tasks, personal is life, drop shows
# as Noise.
BUCKETS = {
    "errands": [
        ("I", "shop.example.com/cart", "Your cart (3 items)", "Soldering tips, flux and a desoldering pump."),
        ("I", "tickets.example.net/booking/7Q2LMX", "Booking 7Q2LMX: train to the coast", "Saturday, 08:12, seat 41."),
        ("M", "library.example.org/account", "Your library account", "Two books due on Friday."),
        ("I", "parcels.example/track/DM2024", "Track your parcel", "Out for delivery."),
        ("M", "my.example.org/billing", "Billing", "Invoice for November."),
        ("I", "maps.example.com/route", "Route to the hardware store", "2.4 km by bike."),
    ],
    "personal": [
        ("I", "recipes.example.com/red-lentil-soup", "Red lentil soup for a weeknight", "Thirty minutes, one pot."),
        ("R", "running.example.org/10k-plan", "A 10k plan for slow runners", "Three runs a week for eight weeks."),
        ("G", "demo.friend.photos", "Picnic Photos", "Birthday picnic at the lake."),
        ("I", "events.example.com/jazz-night", "Jazz night at the community hall", "Thursday at eight."),
        ("I", "wiki:Bonsai", "Bonsai", "Small trees in pots, pruned for years."),
    ],
    "drop": [
        ("I", "news.example.com/live", "Live: transfer rumours", "Updated every few minutes."),
        ("I", "quiz.example.net/appliance", "Which kitchen appliance are you?", "Ten questions."),
        ("X", "demo_memes", "A cat sitting in a cardboard box shaped like a car.", ""),
        ("M", "deals.example.com/gadgets", "Twelve gadgets for your desk", "Sponsored."),
    ],
}

# Links that left their source (closed tabs). They stay in the archive.
ARCHIVED = [
    ("Home Robotics", "tinybots.example", "Encoder wheels from a broken printer", "Two optical encoders, salvaged and wired to a microcontroller."),
    ("Fermentation and Food Science", "saltandtime.example", "Shio koji as a marinade", "Overnight on chicken thighs, then a hot pan."),
    ("Urban Cycling", "streetsmag.example", "The school street experiment", "Closing one street at drop-off time for a term."),
    ("Climate Tech", "gridnotes.example", "Night storage heaters, revisited", "Old hardware, new tariffs."),
    ("Typography and Type Design", "letterpress.example", "Cleaning wood type without damage", "Mineral spirits, a soft brush and no water."),
    ("Deep Sea Biology", "seafloor.example", "Mapping the seafloor by sound", "Multibeam sonar from a small research boat."),
    ("Personal Knowledge Tools", "localfirst.example", "Sync conflicts in plain text files", "What happens when two devices edit the same note."),
    ("Architecture and Housing", "archreview.example", "Prefab bathroom pods", "Built in a factory, craned into place."),
]

# Same page saved twice, found by URLKey.normalize: (theme, index in that
# theme's links, the variant URL saved on the iPhone).
DUPLICATES = [
    ("Fermentation and Food Science", 1, "https://saltandtime.example/a-beginners-guide-to-koji-at-home?utm_source=newsletter"),
    ("Urban Cycling", 1, "https://www.streetsmag.example/how-one-city-doubled-bike-trips-in-five-years?ref=homepage"),
    ("Climate Tech", 0, "https://en.wikipedia.org/wiki/Heat_pump#Efficiency"),
]

# Pages that are gone (404 or no such site): theme, index. Two archived ones
# are added by the generator.
GONE = [("Home Robotics", 10), ("Climate Tech", 13)]

# The user's own notes on links: theme, index, note.
NOTES = [
    ("Home Robotics", 9, "Try this before the summer trip. Pump is in the drawer."),
    ("Fermentation and Food Science", 1, "Rice koji worked on the second try. Keep it at 30 C, not 35."),
    ("Urban Cycling", 13, "Good source for the letter to the council."),
    ("Climate Tech", 11, "Compare with our meter readings in March."),
    ("Typography and Type Design", 6, "Check before using the font in the app."),
    ("Personal Knowledge Tools", 14, "Use this format for the book club."),
]

# Links that also feed a second theme, for the dashed lines on the graph.
CONNECTIONS = [
    ("Home Robotics", 9, "Climate Tech"),
    ("Home Robotics", 4, "Architecture and Housing"),
    ("Fermentation and Food Science", 10, "Home Robotics"),
    ("Urban Cycling", 13, "Climate Tech"),
    ("Urban Cycling", 7, "Architecture and Housing"),
    ("Climate Tech", 0, "Architecture and Housing"),
    ("Climate Tech", 11, "Architecture and Housing"),
    ("Typography and Type Design", 9, "Architecture and Housing"),
    ("Typography and Type Design", 4, "Personal Knowledge Tools"),
    ("Deep Sea Biology", 8, "Climate Tech"),
    ("Deep Sea Biology", 2, "Home Robotics"),
    ("Personal Knowledge Tools", 13, "Synthesizers and Sound"),
    ("Synthesizers and Sound", 14, "Home Robotics"),
    ("Synthesizers and Sound", 7, "Architecture and Housing"),
    ("Architecture and Housing", 7, "Climate Tech"),
]

SAVED_SEARCHES = ["heat pump", "koji", "variable font", "lidar"]

# Longer saved page text for a handful of links: theme, index, text.
ARTICLES = [
    ("Fermentation and Food Science", 1, """Koji is rice or barley with a mould called Aspergillus oryzae growing on it. The mould makes enzymes that break starch into sugar and protein into amino acids, and that is where the sweetness of miso and the depth of soy sauce come from.

You need steamed rice, koji spores, a clean cloth and somewhere that stays at about 30 C for two days. A cooler box with a heating pad and a cheap thermometer is enough. Spread the rice in a thin layer, dust it with spores, cover it and wait.

After about 18 hours the rice smells like chestnuts and you can see a white fuzz. Break up the clumps so air gets in. By 40 to 48 hours the grains should be covered in white. If you see green or yellow, it went too far and started to make spores.

Use the koji fresh, dry it, or freeze it. Shio koji, a mix of koji, salt and water, is the easiest place to start."""),
    ("Climate Tech", 1, """Battery storage now wins auctions for peak capacity that gas plants used to win. Four years of auction results show the price per kilowatt of battery capacity falling by more than half, while gas turbine prices rose with demand for new turbines.

Peaker plants run only a few hundred hours a year, when demand is highest. That makes them a good match for batteries, which charge when power is cheap and discharge for two to four hours in the evening.

The batteries do not replace every gas plant. Long cold spells with little wind still need firm power for days, not hours. But for the daily evening peak, the numbers have changed, and grid operators are changing their plans to match."""),
    ("Urban Cycling", 1, """The city did something unusual: it built a connected network of protected lanes before it argued about each street. In the first year, the council drew a map of 80 kilometres of routes that joined schools, stations and the centre, and built most of it with temporary kerbs and planters.

Bike trips doubled in five years. The biggest increase was in short trips under three kilometres, many of them by women and children, who had not ridden much before.

Shop owners worried about parking. A survey two years later found that most of their customers had arrived on foot, by bike or by tram all along. The temporary kerbs are now being replaced with permanent ones."""),
    ("Typography and Type Design", 1, """A variable font holds a whole range of styles in one file. You draw a few masters, for example a thin and a black weight, and the font interpolates everything in between.

The hard part is keeping the masters compatible. Every glyph needs the same number of points, in the same order, in every master. One extra point in the bold g and the interpolation breaks, and you only notice it at weight 512.

My first year taught me to draw the extremes first, test the middle often, and keep the number of axes small. Weight and optical size cover most needs. Every extra axis multiplies the work."""),
    ("Deep Sea Biology", 0, """Hydrothermal vents are places where seawater seeps into the crust, heats up near magma and comes back out loaded with minerals. The water can be hotter than 350 C and does not boil because of the pressure.

Around the vents live animals that do not depend on sunlight. Bacteria use the chemical energy in hydrogen sulfide to make food, and tube worms, clams and shrimp live off those bacteria, some of them with the bacteria inside their own bodies.

The first vents were found in 1977 near the Galapagos Islands. Since then researchers have found hundreds, on every ocean ridge they have searched."""),
    ("Personal Knowledge Tools", 1, """I used five note apps in twelve months, each for at least two months. I moved my notes every time, which taught me more than the apps did.

What stuck: plain text files in folders, with dates in the file names. Every app could open them, every search tool could index them, and moving them took seconds.

What did not stick: tags. I tagged with care for three weeks and then stopped. Search found everything the tags would have found.

The one feature I miss from the fancier apps is backlinks. I solved that with a search for the file name."""),
    ("Synthesizers and Sound", 1, """Subtractive synthesis starts with a bright, harmonically rich wave from an oscillator, usually a sawtooth or a square. A filter then removes part of the sound, most often the high frequencies. An amplifier controlled by an envelope shapes how loud the sound is over time.

That is the whole chain: oscillator, filter, amplifier, envelope. Most classic synthesizer sounds come from changing just two things, the filter cutoff and the envelope's attack and decay.

Start with one oscillator and the filter fully open. Close the filter slowly while a note plays and listen to the sound get darker. Then give the filter its own envelope and you have the sound of most bass lines from the 1980s."""),
    ("Architecture and Housing", 1, """About half of the people in Vienna live in housing that the city built or subsidised. The city started building in the 1920s and never stopped. It owns about 220,000 flats and supports many more built by nonprofit associations.

Rents in these flats are set to cover costs, not to make a profit. Income limits apply when you move in, but not afterwards, so the buildings house a mix of incomes.

The city also buys land early, before prices rise, and runs design competitions for new projects. The result is a large stock of good, ordinary housing that keeps private rents in check too."""),
]

# YouTube videos with a transcript in the library: theme, index, seconds, transcript.
TRANSCRIPTS = [
    ("Home Robotics", 3, 754, """Today we are testing a servo and a stepper on the same arm. The arm is cheap, printed, and the payload is a kitchen scale so we can read the force.

First the servo. It is quick and it holds position well, but when we push past about 400 grams the gears start to buzz and it drifts.

Now the stepper with a small gearbox. Slower to move, but it holds 900 grams without complaint. The catch is that it does not know where it is if it skips a step, so we add an end stop.

My pick for a desk arm: steppers on the shoulder and elbow, a servo on the gripper."""),
    ("Fermentation and Food Science", 11, 1312, """This is day one. Soybeans soaked overnight, cooked until you can crush one between two fingers. We mash them, mix in the koji and the salt, and pack it into the crock with no air pockets.

Day thirty. We open it, and there is a little mould on top, which is normal. Scrape it off. The paste underneath smells sweet and a bit like soy sauce.

Day ninety. The color is light brown and the taste is salty, sweet and deep. This is a young white miso. You can leave it for a year if you want it darker and stronger."""),
    ("Deep Sea Biology", 2, 10800, """We are at about 1,200 metres on the edge of a cold seep. On the left you can see the mussel bed. The mussels have bacteria in their gills that live on methane coming out of the seafloor.

The white patches are bacterial mats. Further up there are tube worms, and here is an octopus that has been following the vehicle for ten minutes.

We take a push core here, a short tube of sediment, to look at the microbes back in the lab."""),
]

# Where links were sent: destination id, theme, index list.
SENT = {
    "demo-obsidian": [
        ("Home Robotics", [0, 1, 9]),
        ("Fermentation and Food Science", [1, 6, 10, 12]),
        ("Personal Knowledge Tools", [0, 1, 6, 9, 13, 14]),
        ("Synthesizers and Sound", [1, 6, 10]),
        ("Typography and Type Design", [1, 6, 10, 13]),
    ],
    "demo-starlings": [
        ("Climate Tech", [1, 3, 6, 9]),
        ("Architecture and Housing", [1, 6, 7, 14]),
        ("Urban Cycling", [1, 13]),
    ],
}

# Theme default destinations.
SEND_TO = {
    "Personal Knowledge Tools": "demo-obsidian",
    "Typography and Type Design": "demo-obsidian",
    "Climate Tech": "demo-starlings",
    "Architecture and Housing": "demo-starlings",
}

# Theme history: (date, line). The last count is filled in.
HISTORY = [
    ("2026-08-30", "found, {a} links"),
    ("2026-10-04", "rediscovered, {b} links (was {a})"),
    ("2026-11-10", "rediscovered, {c} links (was {b})"),
]

INSTAGRAM_COLLECTIONS = {
    "Workshop": ["demo.makerspace", "demo.robot.garden", "demo.modular.room"],
    "Kitchen": ["demo.ferment.club"],
    "Drawing": ["demo.letterforms", "demo.deep.blue"],
}

X_NAMES = {
    "demo_botbench": "Bench Bot (demo)",
    "demo_sourcrock": "Sour Crock (demo)",
    "demo_bikelanes": "Bike Lane Counter (demo)",
    "demo_gridwatch": "Grid Watch (demo)",
    "demo_typenerd": "Type Notes (demo)",
    "demo_abyssal": "Abyssal Notes (demo)",
    "demo_plaintext": "Plain Text (demo)",
    "demo_patchbay": "Patch Bay (demo)",
    "demo_buildbetter": "Build Better (demo)",
    "demo_memes": "Box Cats (demo)",
}
