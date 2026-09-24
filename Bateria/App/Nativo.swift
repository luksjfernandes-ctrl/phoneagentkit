import Contacts
import EventKit
import Foundation
import Photos

/// Camada de dados nativa. Agente e gabarito leem da MESMA loja, no mesmo processo e na mesma rodada.
enum Nativo {
    nonisolated(unsafe) static let loja = EKEventStore()
    static let fuso = TimeZone(identifier: "America/Sao_Paulo")!
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = fuso; c.locale = Locale(identifier: "pt_BR"); return c }

    static func formato(_ f: String, _ idioma: String = "pt_BR") -> DateFormatter {
        let d = DateFormatter(); d.locale = Locale(identifier: idioma); d.timeZone = fuso; d.dateFormat = f; return d
    }
    static let dia = formato("yyyy-MM-dd")
    static let hora = formato("HH:mm")
    static let rotuloDia = formato("EEEE dd/MM/yyyy")

    struct Evento: Codable { let titulo: String; let inicio: Date; let fim: Date; let diaTodo: Bool }
    struct Lembrete: Codable { let titulo: String; let vence: Date?; let lista: String; let temHora: Bool }
    struct Contato: Codable { let nome: String; let telefones: [String]; let emails: [String] }

    // MARK: Agenda

    static func eventos(de i: Date, ate f: Date) -> [Evento] {
        loja.events(matching: loja.predicateForEvents(withStart: i, end: f, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
            .map { Evento(titulo: $0.title ?? "", inicio: $0.startDate, fim: $0.endDate, diaTodo: $0.isAllDay) }
    }

    static func inicioDoDia(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static func maisDias(_ n: Int, _ d: Date) -> Date { cal.date(byAdding: .day, value: n, to: d)! }

    /// Próximo dia da semana estritamente depois de hoje (1 = domingo … 7 = sábado).
    static func proximo(_ diaSemana: Int, depoisDe hoje: Date) -> Date {
        var d = maisDias(1, inicioDoDia(hoje))
        while cal.component(.weekday, from: d) != diaSemana { d = maisDias(1, d) }
        return d
    }

    // MARK: Lembretes

    static func lembretesAbertos() async -> [Lembrete] {
        await withCheckedContinuation { c in
            loja.fetchReminders(matching: loja.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { rs in
                c.resume(returning: (rs ?? []).map { r in
                    let comps = r.dueDateComponents
                    let data = comps.flatMap { cal.date(from: $0) }
                    return Lembrete(titulo: r.title ?? "", vence: data, lista: r.calendar?.title ?? "", temHora: comps?.hour != nil)
                })
            }
        }
    }

    static func listasDeLembretes() -> [String] { loja.calendars(for: .reminder).map(\.title).sorted() }

    /// Atrasado = aberto com data < agora (sem hora: vence no fim do dia).
    static func atrasado(_ l: Lembrete, agora: Date) -> Bool {
        guard let v = l.vence else { return false }
        return (l.temHora ? v : maisDias(1, inicioDoDia(v))) < agora
    }

    // MARK: Contatos

    static func contatos(nome: String) -> [Contato] {
        let chaves = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let achados = (try? CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: nome), keysToFetch: chaves)) ?? []
        return achados.map(contato)
    }

    static func todosComTelefone() -> [Contato] {
        let chaves = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        var todos: [Contato] = []
        try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: chaves)) { c, _ in
            let k = contato(c); if !k.telefones.isEmpty && !k.nome.trimmingCharacters(in: .whitespaces).isEmpty { todos.append(k) }
        }
        return todos
    }

    static func contato(_ c: CNContact) -> Contato {
        Contato(nome: "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces),
                telefones: c.phoneNumbers.map(\.value.stringValue), emails: c.emailAddresses.map { $0.value as String })
    }

    // MARK: Fotos (só metadado)

    static func ultimaFoto() -> Date? {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 1
        return PHAsset.fetchAssets(with: .image, options: o).firstObject?.creationDate
    }
}

enum Permissoes {
    static func pedir(log: @Sendable (String) -> Void) async -> Bool {
        let agenda = (try? await Nativo.loja.requestFullAccessToEvents()) ?? false
        let lembretes = (try? await Nativo.loja.requestFullAccessToReminders()) ?? false
        let contatos = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        let fotos = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        log("permissões: agenda=\(agenda) lembretes=\(lembretes) contatos=\(contatos) fotos=\(fotos.rawValue)")
        return agenda && lembretes && contatos
    }
}
