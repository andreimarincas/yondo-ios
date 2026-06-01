//
//  SceneConfig.swift
//  Yondo
//
//  Created by Andrei Marincas on 23.12.2025.
//

import Foundation

/// Configuration for a generated scene, including environment, mood, lighting, camera, and optional destination.
nonisolated struct SceneConfig: Hashable, Codable, Sendable {
    /// The main environment for the scene (e.g., city, beach, studio).
    var environment: SceneEnvironment
    /// The mood to convey in the scene (e.g., cinematic, playful).
    var mood: SceneMood
    /// The lighting style for the scene (e.g., daylight, night).
    var lighting: SceneLighting
    /// The camera style or framing for the scene (e.g., portrait, wide).
    var camera: CameraStyle
    /// The specific destination or landmark, if any, for the scene.
    var destination: SceneDestination?
    
    /**
     Generates a detailed prompt string for AI scene generation based on the current configuration.
     
     - Parameters:
        - selfieDescription: A description of the subject (default is "the user").
        - includeSecretViewpoints: Whether to include secret/randomized viewpoints in the prompt.
        - includeSeed: Whether to include a random seed for variation (default is true).
     
     - Returns: A string prompt describing the scene for generation.
     */
    func makePrompt(for selfieDescription: String = "the user", includeSecretViewpoints: Bool, includeSeed: Bool = true) -> String {
        if let _ = destination {
            return makeDestinationPrompt(for: selfieDescription, includeSecretViewpoints: includeSecretViewpoints, includeSeed: includeSeed)
        } else {
            return makeNonDestinationPrompt(for: selfieDescription, includeSeed: includeSeed)
        }
    }

    /// Generates a prompt for scenes with a destination.
    private func makeDestinationPrompt(for selfieDescription: String = "the user", includeSecretViewpoints: Bool, includeSeed: Bool = true) -> String {
        guard let dest = destination else {
            // Fallback to non-destination prompt if destination is missing
            return makeNonDestinationPrompt(for: selfieDescription, includeSeed: includeSeed)
        }
        let seed = Int.random(in: 0..<10_000)

        let destinationLine = "Location: \(dest.title), \(dest.subtitle). Iconic landmark visible and recognizable in the background, with natural variation in viewpoint, distance, and framing."

        let viewpoint = SceneViewpoints.randomViewpoint(destination: destination, environment: environment, includeSecretViewpoints: includeSecretViewpoints)

        let cleanedViewpointDescription = cleanContextualText(
            viewpoint?.description ?? "",
            environment: environment,
            lighting: lighting,
            mood: mood
        )

        return """
        Create a highly photorealistic cinematic scene featuring \(selfieDescription).

        Identity:
        – Use the provided image as the primary identity reference
        – Preserve facial structure, skin tone, age, and likeness
        – Do not alter the user's facial identity
        – Ensure facial features match the provided selfie exactly, including expression and head orientation
        – Skin texture, hair, and eye details must remain faithful
        – Subject’s pose and proportions must be physically realistic
        \(facialExpressionHint)
        
        Pose / Interaction Instructions:
        – Subject may be sitting, standing, or performing an activity appropriate for the environment
        – Pose must be physically plausible and naturally integrated
        – Clothing and body shape should remain consistent with selfie, but can adapt for realism (e.g., t-shirt drapes naturally)

        \(destinationLine)
        
        Environment:
        \(environment.title).
        
        Viewpoint:
        \(cleanedViewpointDescription)

        Mood:
        \(mood.title).

        Lighting:
        \(lighting.title), physically realistic light behavior, natural shadows, global illumination.

        Camera:
        \(camera.title).
        Camera placement should feel natural and cinematic, not handheld selfie-style.
        – Slight variation in camera angle, depth of field, and perspective for realism
        Camera effects:
        – Portrait: slight depth-of-field blur for background
        – Wide: realistic perspective with minimal distortion
        – Close: sharp focus on subject, soft background
        – Dramatic: cinematic lighting and shadows emphasizing subject
        
        Environment Realism:
        – Background landmarks and objects must appear at realistic scale and perspective
        – Environmental lighting, reflections, and shadows should match the subject
        – Avoid repeated or static landmark compositions across generations
        
        Composition:
        – Subject is naturally integrated into the scene, not posed as a selfie
        – Medium or full-body framing when appropriate
        – Natural perspective consistent with the environment
        – Realistic scale between subject and background
        – Balanced framing with depth and foreground/background separation

        Visual realism:
        – Photographic realism, high resolution
        – Natural skin tones and textures
        – Real-world materials and surfaces
        – No cartoon, illustration, or stylized look

        Subtle scene dynamism:
        – Gentle environmental motion implied (e.g. drifting clouds, soft waves, moving leaves, light wind in clothing or hair)
        – Motion should be subtle and realistic, not exaggerated
        – Variations in lighting angle per generation.
        – Minor crowd or wildlife activity in background for realism.
        – Optional seasonal cues (fall leaves, snow) if appropriate.
        – Seasonal cues: autumn leaves, spring flowers, snow, or summer greenery if appropriate
        – Minor wildlife or pedestrian activity, subtle and natural
        – Variation in wind direction, lighting angle, or water movement per generation
        \(environmentMicroDetails)

        Variation & uniqueness:
        – Slightly different lighting angles
        – Minor background activity changes
        – Natural imperfections
        – Avoid repeating identical landmark compositions across generations
        – Optional seasonal elements if appropriate (fall leaves, snow, spring flowers, morning mist)
        – Light angle and intensity varies naturally with time of day
        – Minor details: scattered leaves, distant birds, reflections on surfaces, subtle textures
        – Objects and props appear naturally integrated, not floating or out of place

        Physical constraints:
        – The user is standing or sitting on solid ground
        – Not submerged, not floating, not swimming
        – Pose must be physically plausible and safe
        
        Consistency Between Subject and Scene:
        – Make sure the subject’s lighting matches scene lighting (shadows, highlights, direction of sun).
        – Add interaction with environment (foot on ground, water ripples around feet if standing on beach).
        
        \(genericBoost)
        
        \(cleanContextualText(destinationBoost,
                              environment: environment,
                              lighting: lighting,
                              mood: mood))

        Randomization / Variation:
        – Each generation should introduce slight natural variation in background objects, camera angle, and lighting
        – Include minor random elements like birds, clouds, or people in background
        – Avoid identical positioning of the subject relative to landmarks
        
        Generation seed: \(includeSeed ? seed : 0)
        """
    }
    
    /// Generates a prompt for scenes without a destination.
    private func makeNonDestinationPrompt(for selfieDescription: String = "the user", includeSeed: Bool = true) -> String {
        let seed = Int.random(in: 0..<10_000)
        return """
        Create a highly photorealistic cinematic scene featuring \(selfieDescription).

        Identity:
        – Use the provided image as the primary identity reference
        – Preserve facial structure, skin tone, age, and likeness
        – Do not alter the user's facial identity
        – Ensure facial features match the provided selfie exactly, including expression and head orientation
        – Skin texture, hair, and eye details must remain faithful
        – Subject’s pose and proportions must be physically realistic
        \(facialExpressionHint)
        
        Pose / Interaction Instructions:
        – Subject may be sitting, standing, or performing an activity appropriate for the environment
        – Pose must be physically plausible and naturally integrated
        – Clothing and body shape should remain consistent with selfie, but can adapt for realism (e.g., t-shirt drapes naturally)

        Environment:
        \(environment.title).
        Must remain plausible and realistic for the chosen environment.

        Mood:
        \(mood.title).

        Lighting:
        \(lighting.title), physically realistic light behavior, natural shadows, global illumination.

        Camera:
        \(camera.title).
        Camera placement should feel natural and cinematic, not handheld selfie-style.
        – Slight variation in camera angle, depth of field, and perspective for realism
        Camera effects:
        – Portrait: slight depth-of-field blur for background
        – Wide: realistic perspective with minimal distortion
        – Close: sharp focus on subject, soft background
        – Dramatic: cinematic lighting and shadows emphasizing subject

        Environment Realism:
        – Background objects must appear at realistic scale and perspective
        – Environmental lighting, reflections, and shadows should match the subject
        – Avoid repeated or static compositions across generations
        
        Composition:
        – Subject is naturally integrated into the scene
        – Medium or full-body framing when appropriate
        – Realistic scale between subject and background
        – Balanced framing with depth and foreground/background separation

        Visual realism:
        – Photographic realism, high resolution
        – Natural skin tones and textures
        – Real-world materials and surfaces
        – No cartoon, illustration, or stylized look

        Subtle scene dynamism:
        – Gentle environmental motion implied (e.g. drifting clouds, soft waves, moving leaves, light wind in clothing or hair)
        – Motion should be subtle and realistic, not exaggerated
        – Seasonal cues: autumn leaves, spring flowers, snow, or summer greenery if appropriate
        – Minor wildlife or pedestrian activity, subtle and natural
        – Variation in wind direction, lighting angle, or water movement per generation
        \(environmentMicroDetails)

        Variation & uniqueness:
        – Slightly different lighting angles
        – Minor background activity changes
        – Natural imperfections
        – Optional seasonal elements if appropriate
        – Light angle and intensity varies naturally with time of day
        – Minor details: scattered leaves, distant birds, reflections on surfaces, subtle textures
        – Objects and props appear naturally integrated, not floating or out of place

        Physical constraints:
        – The user is standing or sitting on solid ground
        – Not submerged, not floating, not swimming
        – Pose must be physically plausible and safe
        
        Consistency Between Subject and Scene:
        – Make sure the subject’s lighting matches scene lighting (shadows, highlights, direction of sun).
        – Add interaction with environment (foot on ground, water ripples around feet if standing on beach).
        
        \(genericBoost)

        Randomization / Variation:
        – Each generation should introduce slight natural variation in background objects, camera angle, and lighting
        – Include minor random elements like birds, clouds, or people in background
        – Avoid identical positioning of the subject relative to elements
        
        Generation seed: \(seed)
        """
    }
    
    private var environmentMicroDetails: String {
        if environment == .studio || environment == .luxuryInterior {
            return """
        – Gentle indoor motion (curtains, light reflections, subtle prop shifts)
        – Soft shadows and highlights matching light sources
        – Minor natural imperfections on surfaces
        """
        } else {
            return """
        – Slight wind affecting hair or clothing subtly
        – Reflections on water or glass surfaces if present
        – Minor shadow cast from nearby objects
        – Tiny natural elements like sand grains, leaves, or subtle ripples
        """
        }
    }
    
    private var facialExpressionHint: String {
        return """
        – Subject’s facial expression may hint at the selected mood (\(mood.title)) in a subtle and natural way, without altering identity or likeness\(mood == .playful ? ", facial expression changes should be minimal to avoid unnatural distortions; ensure adjustments are very slight to maintain realism and avoid exaggerated expressions" : "")
        – Minor adjustments only; facial features should primarily match the reference selfie
        """
    }
    
    private var genericBoost: String {
        "Ensure ultra-high realism with natural textures, accurate lighting physics, and seamless integration of all elements."
    }
    
    private var destinationBoost: String {
        guard let dest = destination else { return "" }
        switch dest {
        case .eiffelTower:
            return "Photorealistic Paris atmosphere with realistic urban scale of the Eiffel Tower, subtle street-level activity, pedestrians and vehicles in the background, layered city depth, and natural architectural detail."
        case .grandCanyon:
            return "Vast natural scale with detailed rock formations, layered erosion patterns, deep spatial depth, subtle atmospheric haze, and minor wildlife like birds in the distance."
        case .maldives:
            return "Crystal-clear turquoise water with gentle waves, realistic water refraction and surface detail, natural sand textures, palm trees with subtle motion, and high‑realism tropical beach scenery."
        case .newYork:
            return "Dense urban realism with accurate city proportions, cinematic street-level perspective, realistic traffic and pedestrian flow, strong architectural presence, and layered reflections on glass and steel surfaces."
        case .tokyo:
            return """
                Authentic Tokyo architecture, dense urban detail, balanced modern and traditional elements,
                realistic street scale, layered signage and textures, subtle atmospheric depth,
                high-density city realism without implying a specific time of day.
                """
        case .dubai:
            return "Modern skyline with iconic skyscrapers, realistic glass and steel materials, strong sense of scale, urban depth, and subtle motion in city streets and surrounding environment."
        case .santorini:
            return "Whitewashed buildings on cliffs overlooking the sea, strong architectural contrast, layered coastal depth, natural textures on stone and plaster, and balanced composition between land and water."
        case .machuPicchu:
            return "Ancient mountain ruins with dramatic elevation changes, layered stone terraces, lush surrounding vegetation, atmospheric depth across valleys, and a strong sense of historical scale."
        case .sydney:
            return "Harbor landscape featuring the Opera House and bridge, realistic water reflections, balanced urban and coastal composition, architectural clarity, and natural environmental depth."
        case .cappadocia:
            return "Vast Cappadocia landscape with dozens of hot air balloons floating at varying distances and heights, soft atmospheric haze, layered depth across valleys and rock formations, cinematic scale, gentle environmental motion, and a strong sense of altitude and openness."
        }
    }
}

extension SceneConfig {
    /// The default scene configuration.
    static let `default` = SceneConfig(
        environment: .city,
        mood: .cinematic,
        lighting: .goldenHour,
        camera: .portrait,
        destination: .eiffelTower
    )
}

/// The main type of environment for a scene (e.g., beach, city, studio).
nonisolated enum SceneEnvironment: String, CaseIterable, Identifiable, Codable, Sendable {
    case beach            // Beach or seaside environments
    case city             // Urban/city environments
    case luxuryInterior   // High-end indoor interiors
    case nature           // Natural outdoor environments (forest, mountain, etc.)
    case studio           // Indoor studio environments

    var id: String { rawValue }

    /// Human-readable title for the environment.
    var title: String {
        switch self {
        case .beach: return "Beach"
        case .city: return "City"
        case .luxuryInterior: return "Luxury"
        case .nature: return "Nature"
        case .studio: return "Studio"
        }
    }
    
    /// Name of the thumbnail image for this environment.
    var thumbnailName: String {
        rawValue
    }
}

/// The mood or emotion to be conveyed in the scene.
nonisolated enum SceneMood: String, CaseIterable, Identifiable, Codable, Sendable {
    case cinematic    // Dramatic, film-like mood
    case relaxed      // Calm, peaceful mood
    case confident    // Bold, assertive mood
    case mysterious   // Enigmatic, intriguing mood
    case playful      // Fun, lighthearted mood

    var id: String { rawValue }

    /// Human-readable title for the mood.
    var title: String {
        rawValue.capitalized
    }
    
    /// Name of the thumbnail image for this mood.
    var thumbnailName: String {
        rawValue
    }
}

/// The lighting conditions for the scene.
nonisolated enum SceneLighting: String, CaseIterable, Identifiable, Codable, Sendable {
    case daylight      // Bright daylight lighting
    case goldenHour    // Warm, sunset/sunrise lighting
    case night         // Nighttime lighting
    case neon          // Neon/urban night lighting

    var id: String { rawValue }

    /// Human-readable title for the lighting style.
    var title: String {
        switch self {
        case .daylight: return "Day"
        case .goldenHour: return "Sunset"
        case .night: return "Night"
        case .neon: return "Neon"
        }
    }
}

/// The camera style or framing for the scene.
nonisolated enum CameraStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case portrait   // Portrait orientation or framing
    case wide       // Wide-angle or landscape framing
    case closeUp    // Close-up framing on subject
    case dramatic   // Cinematic/dramatic camera effects

    var id: String { rawValue }

    /// Human-readable title for the camera style.
    var title: String {
        switch self {
        case .portrait: return "Portrait"
        case .wide: return "Wide"
        case .closeUp: return "Close"
        case .dramatic: return "Dramatic"
        }
    }
}

/// The specific landmark or destination for the scene, if any.
nonisolated enum SceneDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case eiffelTower    // Eiffel Tower, Paris
    case grandCanyon    // Grand Canyon, USA
    case maldives       // Maldives, tropical beach
    case newYork        // New York City
    case tokyo          // Tokyo, Japan
    case dubai          // Dubai, UAE
    case santorini      // Santorini, Greece
    case machuPicchu    // Machu Picchu, Peru
    case sydney         // Sydney, Australia
    case cappadocia     // Cappadocia, Turkey (hot air balloons)

    var id: String { rawValue }

    /// Human-readable title for the destination.
    var title: String {
        switch self {
        case .eiffelTower: return "Eiffel Tower"
        case .grandCanyon: return "Grand Canyon"
        case .maldives: return "Maldives"
        case .newYork: return "New York"
        case .tokyo: return "Tokyo"
        case .dubai: return "Dubai"
        case .santorini: return "Santorini"
        case .machuPicchu: return "Machu Picchu"
        case .sydney: return "Sydney"
        case .cappadocia: return "Cappadocia"
        }
    }

    /// Subtitle or location description for the destination.
    var subtitle: String {
        switch self {
        case .eiffelTower: return "Paris, France"
        case .grandCanyon: return "Arizona, USA"
        case .maldives: return "Tropical Escape"
        case .newYork: return "The Big Apple"
        case .tokyo: return "Neon Metropolis"
        case .dubai: return "UAE, Modern Skyline"
        case .santorini: return "Greece, Cliffside"
        case .machuPicchu: return "Peru, Mountain Ruins"
        case .sydney: return "Australia, Harbor"
        case .cappadocia: return "Turkey, Hot Air Balloons"
        }
    }

    /// Name of the thumbnail image for this destination.
    var thumbnailName: String {
        rawValue
    }
    
    /// Allowed environments for this destination.
    var allowedEnvironments: [SceneEnvironment] {
        switch self {
        case .eiffelTower:
            return [.city]
        case .newYork:
            return [.city]
        case .tokyo:
            return [.city]
        case .grandCanyon:
            return [.nature]
        case .maldives:
            return [.beach, .nature]
        case .dubai:
            return [.city]
        case .santorini:
            return [.beach, .nature]
        case .machuPicchu:
            return [.nature]
        case .sydney:
            return [.city, .nature]
        case .cappadocia:
            return [.nature]
        }
    }

    /// Recommended mood for this destination.
    var recommendedMood: SceneMood {
        switch self {
        case .eiffelTower: return .cinematic
        case .newYork: return .confident
        case .tokyo: return .mysterious
        case .grandCanyon: return .relaxed
        case .maldives: return .playful
        case .dubai: return .cinematic
        case .santorini: return .relaxed
        case .machuPicchu: return .mysterious
        case .sydney: return .cinematic
        case .cappadocia: return .cinematic
        }
    }

    /// Recommended lighting for this destination.
    var recommendedLighting: SceneLighting {
        switch self {
        case .tokyo: return .neon
        case .maldives: return .daylight
        case .grandCanyon: return .goldenHour
        case .dubai: return .daylight
        case .santorini: return .goldenHour
        case .machuPicchu: return .daylight
        case .sydney: return .daylight
        case .cappadocia: return .goldenHour
        default: return .goldenHour
        }
    }

    /// Recommended camera style for this destination.
    var recommendedCamera: CameraStyle {
        switch self {
        case .eiffelTower: return .wide
        case .grandCanyon: return .wide
        case .maldives: return .wide
        case .newYork: return .portrait
        case .tokyo: return .wide
        case .dubai: return .wide
        case .santorini: return .wide
        case .machuPicchu: return .wide
        case .sydney: return .wide
        case .cappadocia: return .wide
        }
    }

    /// Indicates if this destination is premium.
    var isPremium: Bool {
        return Self.premium.contains(self)
    }
    
    /// Indicates if this destination is popular.
    var isPopular: Bool {
        return Self.popular.contains(self)
    }
}

nonisolated extension SceneDestination {
    static let popular: [SceneDestination] = [
        .eiffelTower,
        .grandCanyon,
        .maldives,
        .newYork,
        .santorini
    ]

    static let premium: [SceneDestination] = [
        .tokyo,
        .dubai,
        .cappadocia
    ]

    static let allOrdered: [SceneDestination] = [
        // Popular first
        .eiffelTower,
        .grandCanyon,
        .maldives,
        .newYork,
        .santorini,
        // Then premium
        .tokyo,
        .dubai,
        .cappadocia,
        // Then the rest
        .machuPicchu,
        .sydney
    ]
}

nonisolated extension SceneConfig {
    
    /// Cleans contextual descriptive text by removing words that may conflict
    /// with the selected environment, lighting, or mood.
    /// Used for both viewpoint descriptions and destination boosts.
    func cleanContextualText(_ text: String,
                             environment: SceneEnvironment,
                             lighting: SceneLighting,
                             mood: SceneMood) -> String {
        var cleaned = text

        // Remove conflicting lighting words
        let lightingWords: [SceneLighting: [String]] = [
            .daylight: ["day", "daylight", "morning", "afternoon"],
            .goldenHour: ["sunset", "sunrise", "golden hour"],
            .night: ["night", "evening"],
            .neon: ["neon", "night lighting", "city lights"]
        ]

        if let wordsToRemove = lightingWords[lighting] {
            for word in wordsToRemove {
                cleaned = cleaned.replacingOccurrences(
                    of: word,
                    with: "",
                    options: .caseInsensitive
                )
            }
        }

        // Remove conflicting environment words
        let environmentWords: [SceneEnvironment: [String]] = [
            .beach: ["beach", "ocean", "sea", "sand", "shore"],
            .city: ["city", "street", "urban"],
            .nature: ["forest", "mountain", "cliff", "river"],
            .studio: ["studio", "interior", "room"],
            .luxuryInterior: ["luxury", "interior", "room"]
        ]

        if let wordsToRemove = environmentWords[environment] {
            for word in wordsToRemove {
                cleaned = cleaned.replacingOccurrences(
                    of: word,
                    with: "",
                    options: .caseInsensitive
                )
            }
        }

        // Remove strong mood adjectives to avoid duplication
        let moodWords: [SceneMood: [String]] = [
            .cinematic: ["cinematic", "dramatic"],
            .relaxed: ["relaxed", "calm", "peaceful"],
            .confident: ["confident", "bold", "powerful"],
            .mysterious: ["mysterious", "foggy", "misty", "dark"],
            .playful: ["playful", "fun"]
        ]

        if let wordsToRemove = moodWords[mood] {
            for word in wordsToRemove {
                cleaned = cleaned.replacingOccurrences(
                    of: word,
                    with: "",
                    options: .caseInsensitive
                )
            }
        }

        // Normalize whitespace
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
}
