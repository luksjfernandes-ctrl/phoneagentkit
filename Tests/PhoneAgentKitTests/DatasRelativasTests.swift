import Foundation
import Testing
@testable import PhoneAgentKit

/// Regressões de `RelativeDate.resolve`: frases que davam uma data errada em vez de nil.
@Suite struct DatasRelativasTests {
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!; return c }
    static func d(_ s: String) -> Date {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)!
    }
    static func r(_ frase: String, _ agora: String) -> Date? { RelativeDate.resolve(frase, now: d(agora), calendar: cal) }

    /// Mês fora de 1…12 rolava para outro ano: "15/13" virava 15/01 do ano seguinte e "15/0", 15/12.
    @Test func mesInexistenteDaNil() {
        #expect(Self.r("entregar 15/13 às 10h", "2031-01-10 08:00") == nil)
        #expect(Self.r("entregar 15/0 às 10h", "2031-01-10 08:00") == nil)
        #expect(Self.r("entregar 15/13/2031 às 10h", "2031-01-10 08:00") == nil)
        // continua valendo
        #expect(Self.r("entregar 15/12 às 10h", "2031-01-10 08:00") == Self.d("2031-12-15 10:00"))
    }

    /// Prazo em semanas, horas ou minutos não é entendido pelo resolvedor. Antes caía em "só a hora":
    /// "daqui a 2 semanas às 10h" virava hoje às 10h e "daqui a 2 horas", 02:00.
    @Test func prazoEmSemanasHorasOuMinutosDaNil() {
        #expect(Self.r("daqui a 2 semanas às 10h", "2031-01-10 08:00") == nil)
        #expect(Self.r("em duas semanas às 10h", "2031-01-10 08:00") == nil)
        #expect(Self.r("in 2 weeks at 3pm", "2031-01-10 08:00") == nil)
        #expect(Self.r("in a week at 9am", "2031-01-10 08:00") == nil)
        #expect(Self.r("daqui a 2 horas", "2031-01-10 08:00") == nil)
        #expect(Self.r("lembrar daqui a uma hora", "2031-01-10 08:00") == nil)
        #expect(Self.r("in 3 hours", "2031-01-10 08:00") == nil)
        // continua valendo
        #expect(Self.r("sexta às 10 horas", "2031-01-10 08:00") == Self.d("2031-01-10 10:00"))
        #expect(Self.r("amanhã 10 horas da manhã", "2031-01-10 08:00") == Self.d("2031-01-11 10:00"))
        #expect(Self.r("sexta da semana que vem às 10h", "2031-01-10 08:00") == Self.d("2031-01-17 10:00"))
        #expect(Self.r("daqui a 3 dias às 9h", "2031-01-10 08:00") == Self.d("2031-01-13 09:00"))
    }
}
