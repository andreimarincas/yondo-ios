//
//  SceneViewpoints.swift
//  Yondo
//
//  Created by Andrei Marincas on 29.12.2025.
//

import Foundation

/// Represents a possible viewpoint or camera angle for a generated scene.
/// - description: Human-readable description of the viewpoint.
/// - weight: Relative likelihood of being selected (higher means more likely).
/// - isSecret: If true, this viewpoint is considered "secret" (optional, hidden for free credits).
nonisolated struct SceneViewpoint: Identifiable, Hashable, Sendable {
    let id = UUID()
    let description: String
    let weight: Int
    let isSecret: Bool
    
    init(description: String, weight: Int = 1, isSecret: Bool = false) {
        self.description = description
        self.weight = weight
        self.isSecret = isSecret
    }
}

/// Contains all possible viewpoints for each destination/environment combination.
/// - The catalog maps: SceneDestination → SceneEnvironment → [SceneViewpoint]
/// - If a SceneViewpoint has isSecret == true, it is only available optionally (e.g., hidden for free credits).
nonisolated enum SceneViewpoints: Sendable {
    
    /// All available viewpoints, organized by destination and environment.
    /// Secret viewpoints (isSecret == true) are optional and hidden for free credits.
    static let catalog: [SceneDestination: [SceneEnvironment: [SceneViewpoint]]] = [

        // MARK: - Eiffel Tower
        .eiffelTower: [
            .beach: [
                SceneViewpoint(description: "Along the Seine riverbank with stone embankments", weight: 3),
                SceneViewpoint(description: "Near a bridge over the Seine with water in the foreground", weight: 3),
                SceneViewpoint(description: "By the river in central Paris with the Eiffel Tower visible in the distance", weight: 2),
                SceneViewpoint(description: "On a riverside promenade with the Eiffel Tower in the background", weight: 2),
                SceneViewpoint(description: "Light mist along the Seine with boats and the Eiffel Tower", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden sandbar beneath Pont de Bir-Hakeim with Eiffel Tower looming above", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny riverside cove accessible only at low tide, Eiffel Tower visible in the distance", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "On a Parisian street near the Eiffel Tower", weight: 3),
                SceneViewpoint(description: "Urban setting with cafés and classic Paris architecture", weight: 3),
                SceneViewpoint(description: "City viewpoint with traffic and the Eiffel Tower in the background", weight: 2),
                SceneViewpoint(description: "City scene with the Eiffel Tower prominently visible", weight: 2),
                SceneViewpoint(description: "View from a rooftop terrace with bustling Paris below", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Inside a vintage bookshop with the Eiffel Tower framed through the window", weight: 1, isSecret: true),
                SceneViewpoint(description: "From a hidden alleyway with the tower peeking between old stone buildings", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Inside a luxury Paris apartment overlooking the Eiffel Tower", weight: 3),
                SceneViewpoint(description: "High-end hotel interior with large windows framing the Eiffel Tower", weight: 3),
                SceneViewpoint(description: "Elegant interior with Paris skyline visible outside", weight: 2),
                SceneViewpoint(description: "Chic penthouse living room with Eiffel Tower view", weight: 2),
                SceneViewpoint(description: "Luxurious dining area set for breakfast with cityscape backdrop", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Private art studio with unfinished canvas and Eiffel Tower through the skylight", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secret wine cellar with a tiny window showing the Eiffel Tower", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "In the Champ de Mars gardens near the Eiffel Tower", weight: 3),
                SceneViewpoint(description: "Park setting with trees and open lawns, Eiffel Tower behind", weight: 3),
                SceneViewpoint(description: "Green space in Paris with the landmark rising above", weight: 2),
                SceneViewpoint(description: "Flowering gardens with the Eiffel Tower in view", weight: 2),
                SceneViewpoint(description: "Beneath leafy trees with glimpses of the Eiffel Tower through branches", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Secluded wildflower patch at the edge of the park with Eiffel Tower in light fog", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny hidden pond reflecting the Eiffel Tower among reeds and dragonflies", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Professional studio portrait with a subtle Paris skyline backdrop", weight: 3),
                SceneViewpoint(description: "Clean studio setup with Eiffel Tower softly visible behind", weight: 3),
                SceneViewpoint(description: "Neutral studio lighting with Paris landmark suggested in the background", weight: 2),
                SceneViewpoint(description: "Studio scene inspired by classic Parisian aesthetics", weight: 2),
                SceneViewpoint(description: "Backdrop featuring stylized outlines of the Eiffel Tower", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio scene with a miniature Eiffel Tower model casting dramatic shadows", weight: 1, isSecret: true),
                SceneViewpoint(description: "Vintage black-and-white studio with Parisian window and Eiffel Tower silhouette", weight: 1, isSecret: true)
            ]
        ],

        // MARK: - Grand Canyon
        .grandCanyon: [
            .beach: [
                SceneViewpoint(description: "Along the Colorado River at the canyon floor", weight: 3),
                SceneViewpoint(description: "Rocky riverbank surrounded by towering canyon walls", weight: 3),
                SceneViewpoint(description: "Near calm water within the canyon landscape", weight: 2),
                SceneViewpoint(description: "Gravel bar beside the river with red rock reflections", weight: 2),
                SceneViewpoint(description: "Warm-toned riverbank deep within the canyon", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden sandy alcove accessed only by raft, with soaring canyon walls", weight: 1, isSecret: true),
                SceneViewpoint(description: "Small waterfall-fed pool at the river's edge, surrounded by red rocks", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "At a Grand Canyon visitor overlook", weight: 3),
                SceneViewpoint(description: "Scenic viewpoint with railings and canyon beyond", weight: 3),
                SceneViewpoint(description: "Developed lookout area near the canyon rim", weight: 2),
                SceneViewpoint(description: "Observation deck with tourists gazing across the canyon", weight: 2),
                SceneViewpoint(description: "Visitor center plaza with panoramic canyon views", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "From inside an old watchtower with panoramic canyon windows", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden rooftop of a ranger station overlooking the canyon", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Inside a luxury lodge overlooking the canyon", weight: 3),
                SceneViewpoint(description: "High-end interior with panoramic canyon windows", weight: 3),
                SceneViewpoint(description: "Elegant cabin interior with canyon visible outside", weight: 2),
                SceneViewpoint(description: "Private suite with floor-to-ceiling windows facing the canyon", weight: 2),
                SceneViewpoint(description: "Luxurious lounge with panoramic views over the canyon rim", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Private spa room with an infinity tub facing the canyon cliffs", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secret wine cellar built into the canyon rock with a small window view", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "On a canyon rim trail overlooking vast cliffs", weight: 3),
                SceneViewpoint(description: "Natural viewpoint with layered rock formations", weight: 3),
                SceneViewpoint(description: "Open desert landscape near the canyon edge", weight: 2),
                SceneViewpoint(description: "Desert wildflowers in bloom beside the canyon rim", weight: 2),
                SceneViewpoint(description: "Shaded overlook beneath juniper trees with canyon vistas", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden cave entrance with a narrow view of the canyon below", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny ledge with rare wildflowers and a sweeping view into the canyon depths", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Studio portrait with a canyon-inspired backdrop", weight: 3),
                SceneViewpoint(description: "Clean lighting with canyon textures behind", weight: 3),
                SceneViewpoint(description: "Minimalist studio composition inspired by canyon scenery", weight: 2),
                SceneViewpoint(description: "Backdrop featuring warm red rock gradients", weight: 2),
                SceneViewpoint(description: "Studio scene with layered horizon lines evoking canyon depth", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio with real sandstone boulders and dramatic shadow play", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop with a stylized eagle soaring over the canyon", weight: 1, isSecret: true)
            ]
        ],

        // MARK: - Maldives
        .maldives: [
            .beach: [
                SceneViewpoint(description: "On a white sand beach with turquoise water", weight: 3),
                SceneViewpoint(description: "Shoreline with shallow crystal-clear water", weight: 3),
                SceneViewpoint(description: "Beachfront with palm trees and open ocean", weight: 2),
                SceneViewpoint(description: "Beach with gentle waves and soft pastel sky tones", weight: 2),
                SceneViewpoint(description: "Secluded cove with coral sand and lush greenery", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny sandbank island only visible at low tide, surrounded by reef", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden hammock strung between palms on a deserted islet", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "Near a small island harbor with boats", weight: 3),
                SceneViewpoint(description: "Coastal village area with low-rise buildings", weight: 3),
                SceneViewpoint(description: "Developed island area near the shoreline", weight: 2),
                SceneViewpoint(description: "Island ferry dock with colorful fishing boats", weight: 2),
                SceneViewpoint(description: "Village square with market stalls and ocean breezes", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Rooftop café overlooking the harbor with open sky and sea breeze", weight: 1, isSecret: true),
                SceneViewpoint(description: "Narrow alley between pastel buildings with glimpses of the lagoon", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Inside an overwater villa with ocean view", weight: 3),
                SceneViewpoint(description: "Luxury resort interior with glass walls and sea beyond", weight: 3),
                SceneViewpoint(description: "Elegant tropical interior overlooking the lagoon", weight: 2),
                SceneViewpoint(description: "Spa suite with open-air deck above the water", weight: 2),
                SceneViewpoint(description: "Infinity pool room with panoramic sea horizon", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Private underwater suite with coral reef visible through glass walls", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden meditation room with floor cushions and glowing lagoon visible through glass", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "Tropical greenery near the beach", weight: 3),
                SceneViewpoint(description: "Palm grove with ocean visible through trees", weight: 3),
                SceneViewpoint(description: "Natural island landscape with sand and vegetation", weight: 2),
                SceneViewpoint(description: "Mangrove forest meeting the turquoise lagoon", weight: 2),
                SceneViewpoint(description: "Wildflowers and native plants along a sandy path", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden freshwater spring surrounded by ferns on a remote islet", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny clearing in the jungle with rare orchids and a glimpse of the sea", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Clean studio setup with tropical tones", weight: 3),
                SceneViewpoint(description: "Minimal studio portrait inspired by island light", weight: 3),
                SceneViewpoint(description: "Neutral background with subtle ocean influence", weight: 2),
                SceneViewpoint(description: "Studio lighting echoing tropical ocean hues", weight: 2),
                SceneViewpoint(description: "Backdrop with stylized palm leaf silhouettes", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio with a real sand floor and shells for a tactile island feel", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop featuring a stylized manta ray gliding over coral reefs", weight: 1, isSecret: true)
            ]
        ],

        // MARK: - Cappadocia
        .cappadocia: [
            .beach: [
                SceneViewpoint(description: "Open rocky terrain with wide sky above", weight: 3),
                SceneViewpoint(description: "Flat valley floor suitable for balloon views", weight: 3),
                SceneViewpoint(description: "Open landscape with rock formations and sky", weight: 2),
                SceneViewpoint(description: "Soft ambient light over sandy soil and distant fairy chimneys", weight: 2),
                SceneViewpoint(description: "Edge of a shallow stream cutting through the valley floor", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny hidden oasis with reeds and fairy chimneys reflected in the water", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secluded sandy hollow among the rocks, with wild tulips blooming", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "Stone village streets carved into rock", weight: 3),
                SceneViewpoint(description: "Historic Cappadocia settlement with rock formations", weight: 3),
                SceneViewpoint(description: "Urban setting integrated into natural stone terrain", weight: 2),
                SceneViewpoint(description: "Village square with locals gathering and warm stone surroundings", weight: 2),
                SceneViewpoint(description: "Rooftop terrace with panoramic views of cave dwellings", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Inside a pottery workshop carved into the rock with a window to the valley", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden alleyway between stone houses with a glimpse of hot air balloons", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Inside a luxury cave hotel", weight: 3),
                SceneViewpoint(description: "Elegant stone interior with arched openings", weight: 3),
                SceneViewpoint(description: "High-end cave-style room with soft ambient light", weight: 2),
                SceneViewpoint(description: "Suite with private plunge pool in a cave setting", weight: 2),
                SceneViewpoint(description: "Luxury lounge carved into rock with warm lighting", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Secret wine tasting room deep within a cave, candlelit with fairy chimney view", weight: 1, isSecret: true),
                SceneViewpoint(description: "Private hammam spa carved into volcanic stone, with skylight to the blue sky", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "Valley with fairy chimneys and open sky", weight: 3),
                SceneViewpoint(description: "Natural rock formations with hot air balloons overhead", weight: 3),
                SceneViewpoint(description: "Scenic viewpoint across Cappadocia valleys", weight: 2),
                SceneViewpoint(description: "Wildflower meadows between unique rock spires", weight: 2),
                SceneViewpoint(description: "Hilltop viewpoint above the valleys with expansive sky", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden cave entrance overlooking the valley filled with hot air balloons", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny plateau with ancient petroglyphs and panoramic views", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Studio portrait with earthy stone tones", weight: 3),
                SceneViewpoint(description: "Clean setup inspired by Cappadocia textures", weight: 3),
                SceneViewpoint(description: "Minimal backdrop referencing rock formations", weight: 2),
                SceneViewpoint(description: "Backdrop with stylized hot air balloons and valleys", weight: 2),
                SceneViewpoint(description: "Studio lighting inspired by rocky terrain and open skies", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio with real volcanic tuff rocks and lanterns for a cave-like atmosphere", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop featuring a stylized whirling dervish among fairy chimneys", weight: 1, isSecret: true)
            ]
        ]
        ,

        // MARK: - New York
        .newYork: [
            .beach: [
                SceneViewpoint(description: "Along the Hudson River waterfront", weight: 3),
                SceneViewpoint(description: "Riverside promenade with city skyline", weight: 3),
                SceneViewpoint(description: "Urban shoreline with Manhattan in the background", weight: 2),
                SceneViewpoint(description: "At a pier with views of the Statue of Liberty and skyline", weight: 2),
                SceneViewpoint(description: "East River shoreline with city lights reflecting on the water", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden pebble beach beneath Brooklyn Bridge with city lights above", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny riverside parklet with wildflowers and a distant skyline", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "Busy Manhattan street with skyscrapers", weight: 3),
                SceneViewpoint(description: "Times Square-style urban setting", weight: 3),
                SceneViewpoint(description: "City avenue with traffic and tall buildings", weight: 2),
                SceneViewpoint(description: "View from a high-rise rooftop overlooking Central Park", weight: 2),
                SceneViewpoint(description: "Dense urban scene with neon signage and bustling crowds", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden speakeasy with a one-way mirror view of the city", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny rooftop garden with a secret view of the Empire State Building", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Luxury apartment overlooking Manhattan skyline", weight: 3),
                SceneViewpoint(description: "High-end penthouse interior with city views", weight: 3),
                SceneViewpoint(description: "Elegant interior with large windows facing the skyline", weight: 2),
                SceneViewpoint(description: "Modern loft with designer furnishings and skyline vistas", weight: 2),
                SceneViewpoint(description: "Luxurious dining area with expansive Manhattan skyline views", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Private library with a hidden window facing the Chrysler Building", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secret wine cellar beneath a skyscraper with a tiny city view", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "Central Park pathway with city around", weight: 3),
                SceneViewpoint(description: "Green space with skyscrapers visible", weight: 3),
                SceneViewpoint(description: "Urban park setting in New York", weight: 2),
                SceneViewpoint(description: "Wooded area in Central Park with skyline glimpses", weight: 2),
                SceneViewpoint(description: "Cherry blossoms beside a city lake in Central Park", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny birdwatching hideaway in the Ramble with city sounds in the distance", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden community garden with wild sunflowers and a cityscape backdrop", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Studio portrait with subtle city backdrop", weight: 3),
                SceneViewpoint(description: "Clean studio lighting inspired by NYC tones", weight: 3),
                SceneViewpoint(description: "Minimal background hinting at city textures", weight: 2),
                SceneViewpoint(description: "Backdrop featuring stylized outlines of the Empire State Building", weight: 2),
                SceneViewpoint(description: "Studio scene with cool blue tones inspired by the New York skyline", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio setup with a real subway bench and city mural backdrop", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop with stylized yellow cabs weaving through a painted city street", weight: 1, isSecret: true)
            ]
        ],

        // MARK: - Tokyo
        .tokyo: [
            .beach: [
                SceneViewpoint(description: "Urban waterfront with Tokyo skyline", weight: 3),
                SceneViewpoint(description: "Coastal area near the city with water visible", weight: 3),
                SceneViewpoint(description: "Harbor-side location with modern buildings", weight: 2),
                SceneViewpoint(description: "View from Odaiba beach with Rainbow Bridge and skyline", weight: 2),
                SceneViewpoint(description: "Tokyo Bay with city in the background", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden cove beneath a pier with Rainbow Bridge and city skyline", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny urban beach with driftwood and skyline reflections", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "Busy Tokyo street with signage", weight: 3),
                SceneViewpoint(description: "Urban crossing with dense cityscape", weight: 3),
                SceneViewpoint(description: "Modern city district with tall buildings", weight: 2),
                SceneViewpoint(description: "Rooftop view over Shibuya", weight: 2),
                SceneViewpoint(description: "Quiet side street with cherry blossoms", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden izakaya with a window view of passing trains and city", weight: 1, isSecret: true),
                SceneViewpoint(description: "Narrow alley lined with lanterns, Tokyo Tower visible at the end", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "High-rise apartment overlooking Tokyo", weight: 3),
                SceneViewpoint(description: "Luxury hotel interior with city view", weight: 3),
                SceneViewpoint(description: "Minimalist interior with skyline visible outside", weight: 2),
                SceneViewpoint(description: "Penthouse suite with panoramic windows and cityscape", weight: 2),
                SceneViewpoint(description: "Modern tatami room with Tokyo Tower in the distance", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Private tea room with shoji screens and a hidden city skyline view", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secret rooftop onsen with cityscape below", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "Japanese garden within the city", weight: 3),
                SceneViewpoint(description: "Park setting with traditional elements", weight: 3),
                SceneViewpoint(description: "Green space contrasting modern Tokyo", weight: 2),
                SceneViewpoint(description: "Cherry blossom park with petals falling", weight: 2),
                SceneViewpoint(description: "Wooded area with small pond and city skyline beyond", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny island in a city pond with koi and distant skyscrapers", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden bamboo grove with city sounds", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Studio portrait with clean modern tones", weight: 3),
                SceneViewpoint(description: "Minimal setup inspired by Tokyo aesthetics", weight: 3),
                SceneViewpoint(description: "Neutral studio background with urban influence", weight: 2),
                SceneViewpoint(description: "Backdrop with stylized signage and city silhouettes", weight: 2),
                SceneViewpoint(description: "Studio scene inspired by Tokyo city", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio with real tatami mats and paper lanterns for ambiance", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop with stylized cherry blossoms drifting over city views", weight: 1, isSecret: true)
            ]
        ],

        // MARK: - Dubai
        .dubai: [
            .beach: [
                SceneViewpoint(description: "Beachfront with Dubai skyline rising beyond the sand", weight: 3),
                SceneViewpoint(description: "Sandy shoreline with modern towers along the coast", weight: 3),
                SceneViewpoint(description: "Coastal view with luxury hotels in the background", weight: 2),
                SceneViewpoint(description: "Palm-fringed beach with the Burj Al Arab on the horizon", weight: 2),
                SceneViewpoint(description: "Shoreline with city lights reflecting on the water", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny private island off the coast with distant city skyline", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden cove beneath a palm grove with views of the Burj Khalifa", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "Downtown Dubai with striking modern skyscrapers", weight: 3),
                SceneViewpoint(description: "Urban boulevard lined with iconic towers", weight: 3),
                SceneViewpoint(description: "City setting showcasing futuristic architecture", weight: 2),
                SceneViewpoint(description: "Cityscape with illuminated skyscrapers and lively streets", weight: 2),
                SceneViewpoint(description: "View from a sky bridge connecting soaring towers", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden rooftop garden atop a skyscraper with panoramic views", weight: 1, isSecret: true),
                SceneViewpoint(description: "Inside a gold souk with a small arched window showing city lights", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Luxury penthouse with sweeping views over the city", weight: 3),
                SceneViewpoint(description: "High-end hotel interior with dramatic skyline vistas", weight: 3),
                SceneViewpoint(description: "Elegant modern interior with expansive glass walls", weight: 2),
                SceneViewpoint(description: "Private lounge with panoramic views of the Burj Khalifa", weight: 2),
                SceneViewpoint(description: "Spa suite with cityscape visible from a soaking tub", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Secret cigar lounge with opulent decor and a small city view", weight: 1, isSecret: true),
                SceneViewpoint(description: "Private elevator lobby with mirrored walls and a sliver of skyline", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "Desert landscape just outside the city", weight: 3),
                SceneViewpoint(description: "Sand dunes with the skyline visible in the distance", weight: 3),
                SceneViewpoint(description: "Open desert environment with golden tones", weight: 2),
                SceneViewpoint(description: "Oasis with palm trees and desert flowers", weight: 2),
                SceneViewpoint(description: "Camel trail winding through golden dunes", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden desert canyon with rare desert roses in bloom", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny salt flat reflecting clouds and a distant Dubai skyline", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Studio portrait with warm desert-inspired tones", weight: 3),
                SceneViewpoint(description: "Clean setup inspired by Dubai's luxury aesthetics", weight: 3),
                SceneViewpoint(description: "Neutral background with subtle golden accents", weight: 2),
                SceneViewpoint(description: "Backdrop with abstract desert dunes and stylized skyline shapes", weight: 2),
                SceneViewpoint(description: "Studio scene with hints of glowing desert ambiance", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio with real sand and gold accents for a luxe desert vibe", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop featuring stylized falcons soaring above a futuristic city", weight: 1, isSecret: true)
            ]
        ],

        // MARK: - Santorini
        .santorini: [
            .beach: [
                SceneViewpoint(description: "On a volcanic black sand beach with turquoise Aegean water", weight: 3),
                SceneViewpoint(description: "Coastal cove beneath white cliffside houses", weight: 3),
                SceneViewpoint(description: "Pebble beach with blue-domed churches above", weight: 2),
                SceneViewpoint(description: "Seaside at sunrise with pastel sky and cliffs glowing", weight: 2),
                SceneViewpoint(description: "Hidden cove with dramatic rock formations and bright blue sea", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny sea cave opening to a secret beach with sapphire water", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secluded natural rock pool at the base of volcanic cliffs", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "Along winding whitewashed village streets", weight: 3),
                SceneViewpoint(description: "Cliffside town with iconic blue domes and narrow paths", weight: 3),
                SceneViewpoint(description: "Urban setting with cascading white houses and Aegean view", weight: 2),
                SceneViewpoint(description: "Terrace at sunset overlooking the caldera and village rooftops", weight: 2),
                SceneViewpoint(description: "Village square with bustling cafés and panoramic sea views", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden rooftop patio with a single blue dome and sweeping sea view", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny alleyway between white houses with a glimpse of the caldera", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Inside a luxury villa with infinity pool overlooking the caldera", weight: 3),
                SceneViewpoint(description: "Elegant whitewashed interior with arched windows and sea view", weight: 3),
                SceneViewpoint(description: "High-end suite with terrace facing the blue Aegean", weight: 2),
                SceneViewpoint(description: "Spa room with open-air tub and panoramic sunset colors", weight: 2),
                SceneViewpoint(description: "Minimalist suite with open arches and golden hour light", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Private wine cave with candlelight and a tiny window to the sunset", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden spa grotto carved into the cliff, sea sounds echoing", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "Clifftop viewpoint with panoramic caldera and sea below", weight: 3),
                SceneViewpoint(description: "Natural rocky terrain dotted with wildflowers and olive trees", weight: 3),
                SceneViewpoint(description: "Open hillsides with dramatic volcanic coast views", weight: 2),
                SceneViewpoint(description: "Hiking trail along the rim with spring blooms", weight: 2),
                SceneViewpoint(description: "Olive grove on a hillside overlooking the deep blue sea", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny plateau with rare wild herbs and a sweeping caldera view", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secluded cave opening with a natural window to the blue Aegean", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Studio portrait with bright Mediterranean white and blue tones", weight: 3),
                SceneViewpoint(description: "Clean setup inspired by Santorini's iconic architecture", weight: 3),
                SceneViewpoint(description: "Minimal background with soft pastel blue accents", weight: 2),
                SceneViewpoint(description: "Backdrop with stylized domes and sea horizon", weight: 2),
                SceneViewpoint(description: "Studio lighting reminiscent of midday Mediterranean sunlight", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio with real volcanic stones and whitewashed props for authentic texture", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop featuring stylized fishing boats drifting past white cliffs", weight: 1, isSecret: true)
            ]
        ],

        // MARK: - Machu Picchu
        .machuPicchu: [
            .beach: [
                SceneViewpoint(description: "Mountain riverbank with Andes peaks in view", weight: 3),
                SceneViewpoint(description: "Rocky shoreline near cascading mountain streams", weight: 3),
                SceneViewpoint(description: "Tranquil water feature surrounded by lush greenery", weight: 2),
                SceneViewpoint(description: "River bend with morning mist and distant peaks", weight: 2),
                SceneViewpoint(description: "Pebble shore with flowing water and mountain backdrop", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden hot spring beside the river amid Andean mist", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secluded sandy bend with orchids and distant ruins", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "Historic terraces of Machu Picchu with mountain view", weight: 3),
                SceneViewpoint(description: "Ancient Incan ruins framed by peaks", weight: 3),
                SceneViewpoint(description: "Overlook near developed visitor area with panoramic views", weight: 2),
                SceneViewpoint(description: "Sunrise view along the main stone path through ruins", weight: 2),
                SceneViewpoint(description: "View from Sun Gate overlooking the ancient citadel", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden chamber with a small window to the valley", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny stone terrace offering rare view of ruins and peaks", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Luxury lodge with panoramic Andean views", weight: 3),
                SceneViewpoint(description: "High-end room with floor-to-ceiling windows facing the valley", weight: 3),
                SceneViewpoint(description: "Elegant suite overlooking the mountain terraces", weight: 2),
                SceneViewpoint(description: "Private suite with balcony overlooking the ruins", weight: 2),
                SceneViewpoint(description: "Luxury dining area with sunrise views over the peaks", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Meditation room with Incan motifs and valley panorama", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden wine cellar carved into mountainside with tiny ruin view", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "Trail along mountains overlooking the ruins", weight: 3),
                SceneViewpoint(description: "Lush hillside with ancient stone terraces in view", weight: 3),
                SceneViewpoint(description: "Panoramic vantage of the valley and surrounding peaks", weight: 2),
                SceneViewpoint(description: "Cloud forest edge with orchids and distant mountains", weight: 2),
                SceneViewpoint(description: "Steep slope with grazing llamas and vast valley panorama", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden orchid grove with distant waterfalls and ancient stones", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny lookout with rare condors circling the valley", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Studio portrait inspired by Andean textures", weight: 3),
                SceneViewpoint(description: "Minimalist studio with earthy tones reflecting the mountains", weight: 3),
                SceneViewpoint(description: "Clean setup with subtle ancient stone textures", weight: 2),
                SceneViewpoint(description: "Backdrop evoking terraces and peaks of Machu Picchu", weight: 2),
                SceneViewpoint(description: "Studio lighting mimicking early morning mountain mist", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio with mossy stone props and Andean-inspired textures", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop with stylized llamas grazing near ancient terraces", weight: 1, isSecret: true)
            ]
        ],

        // MARK: - Sydney
        .sydney: [
            .beach: [
                SceneViewpoint(description: "On Bondi Beach with rolling waves and city skyline in the distance", weight: 3),
                SceneViewpoint(description: "Coastal headland with dramatic sandstone cliffs above the surf", weight: 3),
                SceneViewpoint(description: "Golden sand beach with surfers and open Pacific horizon", weight: 2),
                SceneViewpoint(description: "Sheltered cove at sunrise, city buildings faint across the bay", weight: 2),
                SceneViewpoint(description: "Calm tidal pool nestled among rocks with skyline visible", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny rock pool hidden among cliffs, first light sparkling on the water", weight: 1, isSecret: true),
                SceneViewpoint(description: "Secluded beach cave with a framed view of the Opera House across the harbor", weight: 1, isSecret: true)
            ],
            .city: [
                SceneViewpoint(description: "Bustling harborfront with ferries and Opera House visible", weight: 3),
                SceneViewpoint(description: "City street lined with palm trees and iconic Sydney landmarks", weight: 3),
                SceneViewpoint(description: "Modern downtown setting with glass towers and busy sidewalks", weight: 2),
                SceneViewpoint(description: "Circular Quay at dusk, lights reflecting on the water", weight: 2),
                SceneViewpoint(description: "Night view from under the illuminated Harbour Bridge", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Hidden rooftop bar with panoramic harbor and city lights at sunset", weight: 1, isSecret: true),
                SceneViewpoint(description: "Tiny alleyway covered in street art with a peek of the skyline", weight: 1, isSecret: true)
            ],
            .luxuryInterior: [
                SceneViewpoint(description: "Luxury high-rise apartment with sweeping views over Sydney Harbour", weight: 3),
                SceneViewpoint(description: "Designer penthouse interior with floor-to-ceiling windows and Opera House view", weight: 3),
                SceneViewpoint(description: "Elegant modern living space with glass walls facing the water", weight: 2),
                SceneViewpoint(description: "Opulent lounge with panoramic night skyline and harbor lights", weight: 2),
                SceneViewpoint(description: "Dining area with glowing cityscape and boats on the harbor", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Private cinema room with harbor reflections flickering on the screen", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden wine cellar with a tiny porthole window looking out to city lights", weight: 1, isSecret: true)
            ],
            .nature: [
                SceneViewpoint(description: "Harbor-side park with lush lawns and eucalyptus trees", weight: 3),
                SceneViewpoint(description: "Coastal bushland trail overlooking the Pacific and city skyline", weight: 3),
                SceneViewpoint(description: "Open green space with wildflowers and panoramic harbor view", weight: 2),
                SceneViewpoint(description: "Clifftop lookout with native flora and sweeping ocean vistas", weight: 2),
                SceneViewpoint(description: "Shaded gully with ferns and trickling creek near the city", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Tiny wildflower meadow atop a headland with endless blue sea", weight: 1, isSecret: true),
                SceneViewpoint(description: "Hidden fern gully with a creek and glimpses of the skyline above", weight: 1, isSecret: true)
            ],
            .studio: [
                SceneViewpoint(description: "Studio portrait with crisp, bright coastal daylight", weight: 3),
                SceneViewpoint(description: "Clean studio setup inspired by ocean blues and sandy neutrals", weight: 3),
                SceneViewpoint(description: "Neutral background with cool blue and sunlit accents", weight: 2),
                SceneViewpoint(description: "Backdrop featuring stylized sails of the Sydney Opera House", weight: 2),
                SceneViewpoint(description: "Studio lighting reminiscent of clear Australian sunlight", weight: 1),
                // Secret viewpoints
                SceneViewpoint(description: "Studio with real eucalyptus leaves and vibrant blue props", weight: 1, isSecret: true),
                SceneViewpoint(description: "Backdrop with stylized cockatoos and a watercolor Sydney sunrise", weight: 1, isSecret: true)
            ]
        ]
    ]
}

nonisolated extension SceneViewpoints {
    
    /// Selects a random viewpoint for the given destination and environment.
    /// - If includeSecretViewpoints is false, secret viewpoints are excluded.
    /// - Uses weighted random selection based on the `weight` property.
    static func randomViewpoint(
        destination: SceneDestination?,
        environment: SceneEnvironment,
        includeSecretViewpoints: Bool
    ) -> SceneViewpoint? {
        
        guard
            let destination,
            let envMap = catalog[destination],
            var viewpoints = envMap[environment],
            !viewpoints.isEmpty
        else {
            return nil
        }
        
        if !includeSecretViewpoints {
            viewpoints = viewpoints.filter { !$0.isSecret }
        }
        return weightedRandom(viewpoints)
    }
    
    /// Selects one viewpoint from the array using weighted random selection.
    /// Each viewpoint's `weight` determines its probability.
    static func weightedRandom(_ viewpoints: [SceneViewpoint]) -> SceneViewpoint? {
        let totalWeight = viewpoints.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        var random = Int.random(in: 0..<totalWeight)

        for viewpoint in viewpoints {
            random -= viewpoint.weight
            if random < 0 {
                return viewpoint
            }
        }

        return viewpoints.last
    }
    
    /// Temporary testing helper:
    /// Randomly selects only from secret viewpoints for a given destination/environment.
    /// Not for production use.
    static func randomSecretViewpoint(
        destination: SceneDestination?,
        environment: SceneEnvironment
    ) -> SceneViewpoint? {
        guard
            let destination,
            let envMap = catalog[destination],
            let viewpoints = envMap[environment],
            !viewpoints.isEmpty
        else {
            return nil
        }
        
        // Filter only secret viewpoints
        let secretViewpoints = viewpoints.filter { $0.isSecret }
        
        return secretViewpoints.randomElement()
    }
}
