import CoreData
import Foundation
import Testing

@testable import SoundMarks

/// Core Data model integrity.
///
/// CloudKit was removed from the project, but the rules are still useful: map exchange
/// between devices (Phase 3) merges objects by UUID, and the model must
/// survive lightweight migration between phases:
///  * every attribute is either optional or has a default value;
///  * unique constraints are not supported;
///  * every relationship must have an inverse;
///  * ordered relationships are not supported;
///  * the Undefined and ObjectID types are not supported;
///  * the Deny delete rule is not supported.
@Suite("Model integrity")
@MainActor
struct ModelIntegrityTests {
    private var model: NSManagedObjectModel {
        PersistenceController(mode: .inMemory).container.managedObjectModel
    }

    private var entities: [NSEntityDescription] {
        model.entities.filter { !$0.isAbstract }
    }

    @Test("The model contains all expected entities")
    func modelHasExpectedEntities() {
        let names = Set(entities.compactMap(\.name))
        #expect(names == ["Place", "Track", "MediaItem", "MemoryMap", "Trip", "RoutePoint", "Profile"])
    }

    @Test("Every attribute is optional or has a default value")
    func attributesAreOptionalOrDefaulted() {
        for entity in entities {
            for (name, attribute) in entity.attributesByName {
                let isSatisfied = attribute.isOptional || attribute.defaultValue != nil
                #expect(isSatisfied, "\(entity.name ?? "?").\(name) is not optional and has no default value")
            }
        }
    }

    @Test("Unique constraints are not used")
    func noUniquenessConstraints() {
        for entity in entities {
            #expect(entity.uniquenessConstraints.isEmpty,
                    "\(entity.name ?? "?") declares a unique constraint")
        }
    }

    @Test("Every relationship has an inverse, and it points back")
    func everyRelationshipHasInverse() {
        for entity in entities {
            for (name, relationship) in entity.relationshipsByName {
                guard let inverse = relationship.inverseRelationship else {
                    Issue.record("\(entity.name ?? "?").\(name) has no inverse relationship")
                    continue
                }
                #expect(inverse.inverseRelationship == relationship,
                        "\(entity.name ?? "?").\(name): the inverse relationship does not point back")
                #expect(inverse.entity == relationship.destinationEntity,
                        "\(entity.name ?? "?").\(name): the inverse relationship belongs to another entity")
            }
        }
    }

    @Test("Ordered relationships are not used")
    func noOrderedRelationships() {
        for entity in entities {
            for (name, relationship) in entity.relationshipsByName {
                #expect(relationship.isOrdered == false,
                        "\(entity.name ?? "?").\(name) is declared ordered")
            }
        }
    }

    @Test("The Deny delete rule is not used")
    func noDenyDeleteRules() {
        for entity in entities {
            for (name, relationship) in entity.relationshipsByName {
                #expect(relationship.deleteRule != .denyDeleteRule,
                        "\(entity.name ?? "?").\(name) uses Deny")
            }
        }
    }

    @Test("Unsupported attribute types are not used")
    func noUnsupportedAttributeTypes() {
        let unsupported: Set<NSAttributeDescription.AttributeType> = [.undefined, .objectID]
        for entity in entities {
            for (name, attribute) in entity.attributesByName {
                #expect(unsupported.contains(attribute.type) == false,
                        "\(entity.name ?? "?").\(name) has type \(attribute.type)")
            }
        }
    }

    @Test("Entities declare no required scalar attributes without a default")
    func scalarAttributesHaveDefaults() {
        let scalarTypes: Set<NSAttributeDescription.AttributeType> = [
            .boolean, .integer16, .integer32, .integer64, .double, .float, .decimal,
        ]
        for entity in entities {
            for (name, attribute) in entity.attributesByName where scalarTypes.contains(attribute.type) {
                #expect(attribute.defaultValue != nil,
                        "\(entity.name ?? "?").\(name) — scalar without a default value")
            }
        }
    }
}
