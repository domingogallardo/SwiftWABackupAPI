import XCTest
@testable import SwiftWABackupAPI

struct ExpectedMessage {
    let id: Int
    let chatId: Int
    let messageType: String
    let isFromMe: Bool
    let message: String?
    let senderName: String?
    let senderPhone: String?
    let caption: String?
    let mediaFilename: String?
    let replyTo: Int?
    let reactions: [Reaction]?
}

final class FixtureRegressionTests: XCTestCase {
    override func setUpWithError() throws {
        try TestSupport.requireFullFixtureRun()
    }
    
    func testChatNames() throws {
        let chatNames = ["+34 609 43 60 10", "Jose Bonora", "+34 644 40 75 59",
                         "Pilar - Lucía López", "+34 607 37 19 32", "+34 691 99 12 53",
                         "+34 650 56 32 56", "+34 689 25 68 19", "OICV Alicante",
                         "Elías - Elena", "La Pequeña Bodeguita", "+34 607 72 96 77",
                         "Jose Luis Vecino", "Cumpleaños de Juan", "Libreria Valencia",
                         "Llepaplats", "Mari Trini", "Piedad", "+34 618 58 57 21",
                         "Sonia Informatica", "Furbolín", "+34 635 67 23 02",
                         "Vigilancia PA", "Dato", "+34 643 30 34 04", "+34 603 69 84 20",
                         "+34 667 43 12 54", "Muerte del padre de Luis", "+34 676 53 40 61",
                         "+34 663 39 08 06", "+34 609 58 33 90", "+34 657 46 88 50",
                         "Mercedes", "Regalo de navidad de mamá", "Diego", "+34 634 49 07 36",
                         "+54 9 11 2392-2291", "Cena Nochevieja general 😜",
                         "Jose Antonio Belda", "Clara - Sara", "Fernando Padre Gorka",
                         "Angelín", "Otto", "+34 911 65 01 48", "+34 685 43 14 34",
                         "+34 654 73 44 38", "+34 640 80 74 27", "Sandra - Renault ",
                         "Francisco Martinez", "Bufete Sanz Abogados", "Berto Romero",
                         "Juan Padre", "+34 638 10 10 04", "Jesús Peral", "Hugo",
                         "Miguel Cazorla", "Elisa", "Maite", "+34 670 08 64 11",
                         "+34 671 24 67 93", "+39 335 577 0107", "+34 655 44 50 43",
                         "+34 600 86 99 07", "Sonia - Berta", "Me", "Simón Picó",
                         "Nelly", "Jose Luis La Red", "Miguel Ángel Lozano", "Angel",
                         "Mario Profesor Guitarra", "Raquel", "SmartRent", "+34 623 13 94 19",
                         "+34 646 00 89 74", "Juan Puchol", "LPP", "Manolo DCCIA",
                         "+34 626 00 19 34", "Los Clásicos - La Clásica",
                         "Jose Luis Vicedo", "Pierre", "Mábel", "Cristina", "Carmen 💍",
                         "Ana Ruiz - Compañera Piso Lucia", "Ismael - Amigo Lucía",
                         "Marcial", "Comida Experto Java", "Eli", "Aitor Medrano",
                         "✨Familia Gallardo✨", "+34 661 72 41 53", "+34 666 13 17 61",
                         "Julio", "+34 683 77 21 44", "Jose Maria Primo",
                         "+34 973 90 18 71", "Marisa", "+34 616 20 36 56", "Carlos",
                         "Muñaqui", "Fran García", "+34 681 64 90 28", "Miriam Amiga Lucía",
                         "+34 638 74 88 18", "Canadá", "Guillermo Primo",
                         "Comunión de Pablo 2-6-18", "+34 626 06 65 29", "+34 615 45 74 28",
                         "María casera", "Farmacia", "Antonio Botía", "Ofeli - Renault",
                         "Elias primo Conso", "Cristales CristAlacant", "+34 602 40 85 10",
                         "Pablo", "Recogidas Reto", "+34 654 01 18 39", "Casa Rural León",
                         "Apartamento Ponferrada", "Fernando - Taller", "+593 98 722 2270",
                         "Manri", "Jesús", "+34 660 40 49 13", "Juan Gabriel",
                         "Cristobal Infantes", "Casa Rural Valdepielago", "+34 638 70 39 82",
                         "Fisioterapia María Monpó", "Vicente amigo Lucía", "Raquel - Alicia",
                         "+34 687 90 59 73", "Jose Luis Zamora", "Felipe", "Alfons Delaxarxa",
                         "+34 655 96 77 76", "Jose amigo Lucía", "+34 601 27 93 18", "Ana Prima",
                         "OICV 2024 ALC", "OICV", "+92 302 3158598", "Jose A", "+34 622 58 49 76",
                         "Gorka", "Recetas 😋", "60 Años🥳", "Cumple MARI TRINI REGALO",
                         "Paco Moreno", "Luis", "Vinos y risas", "Alejandro Such", "Jorge Calvo",
                         "Vigilancia PPSS", "+34 670 10 35 54", "Fran García", "+34 600 51 29 30",
                         "Miguel Angel", "+34 654 79 31 20", "+34 660 70 93 16",
                         "Los Lopez - primos ", "María Prima", "Perugia", "Mamá", "Family❤️",
                         "Conso", "Lucía 💗", "Instituto Juan Gil Albert", "SENIOR UA",
                         "Anabel 🧡", "Cristina Pomares", "María Pastor"]
        let testBackupPath = TestSupport.fixtureRoot.path
        let waBackup = WABackup(backupPath: testBackupPath)
        do {
            let backups = try waBackup.getBackups()
            guard let iPhoneBackup = backups.validBackups.first else {
                XCTFail("No valid backups found")
                return
            }
            try waBackup.connectChatStorageDb(from: iPhoneBackup)
            let chats = try waBackup.getChats()
            
            // Compare names in chats in the backup with names in the array chatNames.
            // Error if there are some names in backup that are not in the array or
            // there are some names in the array that are not in the backup
            // Extract chat names from the backup
            let activeChats = chats.filter { !$0.isArchived}
            let backupChatNames = Set(activeChats.map { $0.name })
            let expectedChatNames = Set(chatNames)
            
            // Identify extra names in the backup that are not expected
            let extraNames = backupChatNames.subtracting(expectedChatNames)
            
            // Identify missing names that are expected but not found in the backup
            let missingNames = expectedChatNames.subtracting(backupChatNames)
            
            // Assert that there are no extra names
            if !extraNames.isEmpty {
                XCTFail("Found unexpected chat names in backup: \(extraNames)")
            }
            
            // Assert that there are no missing names
            if !missingNames.isEmpty {
                XCTFail("Expected chat names not found in backup: \(missingNames)")
            }
            
            // Finally, assert that both sets are equal
            //XCTAssertEqual(backupChatNames, expectedChatNames, "Chat names in backup do not // match the expected names.")
        } catch {
            XCTFail("Error fetching chats: \(error)")
        }
    }
        
    func testChatIdsAndMessageCounts() throws {
        let testBackupPath = TestSupport.fixtureRoot.path
        let waBackup = WABackup(backupPath: testBackupPath)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // Definir los chats esperados
        
        let expectedChats: [ChatInfo] = [
            ChatInfo(
                id: 224,
                contactJid: "34601180041-1392988325@g.us",
                name: "Family❤️",
                numberMessages: 31249,
                lastMessageDate: dateFormatter.date(from: "2024-10-01 09:42:58")!,
                isArchived: false            ),

            ChatInfo(
                id: 548,
                contactJid: "34608100195@s.whatsapp.net",
                name: "Instituto Juan Gil Albert",
                numberMessages: 523,
                lastMessageDate: dateFormatter.date(from: "2024-09-30 17:21:22")!,
                isArchived: false
            ),

            ChatInfo(
                id: 628,
                contactJid: "120363023390396669@g.us",
                name: "SENIOR UA",
                numberMessages: 9,
                lastMessageDate: dateFormatter.date(from: "2024-09-30 13:15:57")!,
                isArchived: false
            ),

            ChatInfo(
                id: 639,
                contactJid: "34693206402@s.whatsapp.net",
                name: "Me",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2024-09-29 09:30:26")!,
                isArchived: false
            ),

            ChatInfo(
                id: 8,
                contactJid: "34601180041@s.whatsapp.net",
                name: "Lucía 💗",
                numberMessages: 3458,
                lastMessageDate: dateFormatter.date(from: "2024-09-28 10:21:14")!,
                isArchived: false
            ),

            ChatInfo(
                id: 398,
                contactJid: "34686275599@s.whatsapp.net",
                name: "Conso",
                numberMessages: 1533,
                lastMessageDate: dateFormatter.date(from: "2024-09-27 13:36:07")!,
                isArchived: false
            ),

            ChatInfo(
                id: 629,
                contactJid: "34623139419@s.whatsapp.net",
                name: "+34 623 13 94 19",
                numberMessages: 9,
                lastMessageDate: dateFormatter.date(from: "2024-09-25 18:02:53")!,
                isArchived: false            ),

            ChatInfo(
                id: 3,
                contactJid: "34662499450@s.whatsapp.net",
                name: "Anabel 🧡",
                numberMessages: 2927,
                lastMessageDate: dateFormatter.date(from: "2024-09-22 20:08:43")!,
                isArchived: false            ),

            ChatInfo(
                id: 637,
                contactJid: "34654638410@s.whatsapp.net",
                name: "María Pastor",
                numberMessages: 17,
                lastMessageDate: dateFormatter.date(from: "2024-09-22 10:30:09")!,
                isArchived: false            ),

            ChatInfo(
                id: 82,
                contactJid: "34646412707@s.whatsapp.net",
                name: "Mamá",
                numberMessages: 1154,
                lastMessageDate: dateFormatter.date(from: "2024-09-18 21:09:03")!,
                isArchived: false            ),

            ChatInfo(
                id: 7,
                contactJid: "34655468076@s.whatsapp.net",
                name: "Cristina Pomares",
                numberMessages: 3155,
                lastMessageDate: dateFormatter.date(from: "2024-09-12 11:34:45")!,
                isArchived: false            ),

            ChatInfo(
                id: 634,
                contactJid: "34747424369@s.whatsapp.net",
                name: "SmartRent",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2024-09-11 17:36:30")!,
                isArchived: false            ),

            ChatInfo(
                id: 599,
                contactJid: "34646008974@s.whatsapp.net",
                name: "+34 646 00 89 74",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2024-09-10 12:48:02")!,
                isArchived: false            ),

            ChatInfo(
                id: 250,
                contactJid: "34622050558@s.whatsapp.net",
                name: "Juan Puchol",
                numberMessages: 14,
                lastMessageDate: dateFormatter.date(from: "2024-09-08 18:19:56")!,
                isArchived: false            ),

            ChatInfo(
                id: 128,
                contactJid: "34693206402-1489144420@g.us",
                name: "LPP",
                numberMessages: 22774,
                lastMessageDate: dateFormatter.date(from: "2024-09-06 20:29:24")!,
                isArchived: false            ),

            ChatInfo(
                id: 627,
                contactJid: "34669979624@s.whatsapp.net",
                name: "Manolo DCCIA",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2024-09-06 17:12:05")!,
                isArchived: false            ),

            ChatInfo(
                id: 586,
                contactJid: "34626001934@s.whatsapp.net",
                name: "+34 626 00 19 34",
                numberMessages: 15,
                lastMessageDate: dateFormatter.date(from: "2024-08-29 17:12:10")!,
                isArchived: false            ),

            ChatInfo(
                id: 197,
                contactJid: "34699074946-1562514185@g.us",
                name: "Los Clásicos - La Clásica",
                numberMessages: 1206,
                lastMessageDate: dateFormatter.date(from: "2024-08-27 21:47:52")!,
                isArchived: false            ),

            ChatInfo(
                id: 578,
                contactJid: "34610313276@s.whatsapp.net",
                name: "Marcial",
                numberMessages: 64,
                lastMessageDate: dateFormatter.date(from: "2024-08-25 17:56:39")!,
                isArchived: false            ),

            ChatInfo(
                id: 416,
                contactJid: "120363041475816933@g.us",
                name: "Comida Experto Java",
                numberMessages: 468,
                lastMessageDate: dateFormatter.date(from: "2024-07-26 13:07:00")!,
                isArchived: false            ),

            ChatInfo(
                id: 88,
                contactJid: "34672351765@s.whatsapp.net",
                name: "Eli",
                numberMessages: 395,
                lastMessageDate: dateFormatter.date(from: "2024-07-18 18:04:21")!,
                isArchived: false            ),

            ChatInfo(
                id: 44,
                contactJid: "34636104084@s.whatsapp.net",
                name: "Aitor Medrano",
                numberMessages: 153,
                lastMessageDate: dateFormatter.date(from: "2024-07-16 13:45:25")!,
                isArchived: false            ),

            ChatInfo(
                id: 226,
                contactJid: "34693206402-1435507670@g.us",
                name: "✨Familia Gallardo✨",
                numberMessages: 1969,
                lastMessageDate: dateFormatter.date(from: "2024-07-11 21:27:22")!,
                isArchived: false            ),

            ChatInfo(
                id: 626,
                contactJid: "34661724153@s.whatsapp.net",
                name: "+34 661 72 41 53",
                numberMessages: 7,
                lastMessageDate: dateFormatter.date(from: "2024-07-11 12:30:35")!,
                isArchived: false            ),

            ChatInfo(
                id: 625,
                contactJid: "34666131761@s.whatsapp.net",
                name: "+34 666 13 17 61",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2024-07-09 08:14:38")!,
                isArchived: false            ),

            ChatInfo(
                id: 10,
                contactJid: "34657572413@s.whatsapp.net",
                name: "Julio",
                numberMessages: 1004,
                lastMessageDate: dateFormatter.date(from: "2024-07-06 19:15:33")!,
                isArchived: false            ),

            ChatInfo(
                id: 580,
                contactJid: "34610818214@s.whatsapp.net",
                name: "Simón Picó",
                numberMessages: 20,
                lastMessageDate: dateFormatter.date(from: "2024-07-01 11:21:02")!,
                isArchived: false            ),

            ChatInfo(
                id: 621,
                contactJid: "34624461608@s.whatsapp.net",
                name: "Nelly",
                numberMessages: 2,
                lastMessageDate: dateFormatter.date(from: "2024-06-21 20:06:16")!,
                isArchived: false            ),

            ChatInfo(
                id: 575,
                contactJid: "34653018902@s.whatsapp.net",
                name: "Jose Luis La Red",
                numberMessages: 8,
                lastMessageDate: dateFormatter.date(from: "2024-06-17 19:01:21")!,
                isArchived: false            ),

            ChatInfo(
                id: 91,
                contactJid: "34622173664@s.whatsapp.net",
                name: "Miguel Ángel Lozano",
                numberMessages: 143,
                lastMessageDate: dateFormatter.date(from: "2024-06-10 12:37:07")!,
                isArchived: false            ),

            ChatInfo(
                id: 620,
                contactJid: "62838319909242@s.whatsapp.net",
                name: "+62 838-3199-09242",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2024-06-07 18:11:46")!,
                isArchived: true            ),

            ChatInfo(
                id: 34,
                contactJid: "34605100221@s.whatsapp.net",
                name: "Angel",
                numberMessages: 2046,
                lastMessageDate: dateFormatter.date(from: "2024-06-03 22:46:50")!,
                isArchived: false            ),

            ChatInfo(
                id: 205,
                contactJid: "34647748984@s.whatsapp.net",
                name: "Mario Profesor Guitarra",
                numberMessages: 115,
                lastMessageDate: dateFormatter.date(from: "2024-05-27 13:36:07")!,
                isArchived: false            ),

            ChatInfo(
                id: 11,
                contactJid: "34690227762@s.whatsapp.net",
                name: "Raquel",
                numberMessages: 126,
                lastMessageDate: dateFormatter.date(from: "2024-05-20 13:19:19")!,
                isArchived: false            ),

            ChatInfo(
                id: 587,
                contactJid: "34660975831@s.whatsapp.net",
                name: "María casera",
                numberMessages: 60,
                lastMessageDate: dateFormatter.date(from: "2024-05-17 19:06:08")!,
                isArchived: false            ),

            ChatInfo(
                id: 594,
                contactJid: "34680656093@s.whatsapp.net",
                name: "Farmacia",
                numberMessages: 15,
                lastMessageDate: dateFormatter.date(from: "2024-05-16 13:26:47")!,
                isArchived: false            ),

            ChatInfo(
                id: 121,
                contactJid: "34690103286@s.whatsapp.net",
                name: "Antonio Botía",
                numberMessages: 1731,
                lastMessageDate: dateFormatter.date(from: "2024-05-14 11:37:42")!,
                isArchived: false            ),

            ChatInfo(
                id: 617,
                contactJid: "34677779325@s.whatsapp.net",
                name: "Ofeli - Renault",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2024-05-13 14:58:28")!,
                isArchived: false            ),

            ChatInfo(
                id: 512,
                contactJid: "34633291418@s.whatsapp.net",
                name: "Elias primo Conso",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2024-05-12 12:25:01")!,
                isArchived: false            ),

            ChatInfo(
                id: 616,
                contactJid: "34611071269@s.whatsapp.net",
                name: "Cristales CristAlacant",
                numberMessages: 22,
                lastMessageDate: dateFormatter.date(from: "2024-05-08 12:03:15")!,
                isArchived: false            ),

            ChatInfo(
                id: 477,
                contactJid: "34602408510@s.whatsapp.net",
                name: "+34 602 40 85 10",
                numberMessages: 31,
                lastMessageDate: dateFormatter.date(from: "2024-05-07 12:56:06")!,
                isArchived: false            ),

            ChatInfo(
                id: 260,
                contactJid: "34639879552@s.whatsapp.net",
                name: "Pablo",
                numberMessages: 80,
                lastMessageDate: dateFormatter.date(from: "2024-05-06 18:16:44")!,
                isArchived: false            ),

            ChatInfo(
                id: 611,
                contactJid: "34661716484@s.whatsapp.net",
                name: "Sandra - Renault ",
                numberMessages: 34,
                lastMessageDate: dateFormatter.date(from: "2024-05-03 13:29:39")!,
                isArchived: false            ),

            ChatInfo(
                id: 135,
                contactJid: "34649427291@s.whatsapp.net",
                name: "Francisco Martinez",
                numberMessages: 288,
                lastMessageDate: dateFormatter.date(from: "2024-04-15 11:57:12")!,
                isArchived: false            ),

            ChatInfo(
                id: 608,
                contactJid: "34645967879@s.whatsapp.net",
                name: "Bufete Sanz Abogados",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2024-03-28 12:58:31")!,
                isArchived: false            ),

            ChatInfo(
                id: 607,
                contactJid: "34606373058@s.whatsapp.net",
                name: "Berto Romero",
                numberMessages: 2,
                lastMessageDate: dateFormatter.date(from: "2024-03-20 07:23:06")!,
                isArchived: false            ),

            ChatInfo(
                id: 97,
                contactJid: "34655784262@s.whatsapp.net",
                name: "Juan Padre",
                numberMessages: 348,
                lastMessageDate: dateFormatter.date(from: "2024-03-15 14:13:03")!,
                isArchived: false            ),

            ChatInfo(
                id: 593,
                contactJid: "34683772144@s.whatsapp.net",
                name: "+34 683 77 21 44",
                numberMessages: 7,
                lastMessageDate: dateFormatter.date(from: "2024-02-23 20:37:33")!,
                isArchived: false            ),

            ChatInfo(
                id: 596,
                contactJid: "34636354852@s.whatsapp.net",
                name: "Jesús Peral",
                numberMessages: 8,
                lastMessageDate: dateFormatter.date(from: "2024-02-23 11:55:16")!,
                isArchived: false            ),

            ChatInfo(
                id: 544,
                contactJid: "120363027466609818@g.us",
                name: "OICV 2024 ALC",
                numberMessages: 248,
                lastMessageDate: dateFormatter.date(from: "2024-01-26 18:46:56")!,
                isArchived: false            ),

            ChatInfo(
                id: 363,
                contactJid: "120363039560737011@g.us",
                name: "OICV",
                numberMessages: 229,
                lastMessageDate: dateFormatter.date(from: "2024-01-26 12:25:04")!,
                isArchived: false            ),

            ChatInfo(
                id: 597,
                contactJid: "923023158598@s.whatsapp.net",
                name: "+92 302 3158598",
                numberMessages: 2,
                lastMessageDate: dateFormatter.date(from: "2024-01-15 12:49:42")!,
                isArchived: false            ),

            ChatInfo(
                id: 90,
                contactJid: "34660858925@s.whatsapp.net",
                name: "Jose A",
                numberMessages: 123,
                lastMessageDate: dateFormatter.date(from: "2023-12-30 11:55:32")!,
                isArchived: false            ),

            ChatInfo(
                id: 261,
                contactJid: "34622584976@s.whatsapp.net",
                name: "+34 622 58 49 76",
                numberMessages: 17,
                lastMessageDate: dateFormatter.date(from: "2023-12-26 19:45:33")!,
                isArchived: false            ),

            ChatInfo(
                id: 201,
                contactJid: "34682867709@s.whatsapp.net",
                name: "Gorka",
                numberMessages: 229,
                lastMessageDate: dateFormatter.date(from: "2023-12-26 15:05:18")!,
                isArchived: false            ),

            ChatInfo(
                id: 180,
                contactJid: "34662499450-1552740247@g.us",
                name: "Recetas 😋",
                numberMessages: 26,
                lastMessageDate: dateFormatter.date(from: "2023-12-24 19:15:18")!,
                isArchived: false            ),

            ChatInfo(
                id: 433,
                contactJid: "120363025789047013@g.us",
                name: "60 Años🥳",
                numberMessages: 317,
                lastMessageDate: dateFormatter.date(from: "2023-12-24 15:31:44")!,
                isArchived: false            ),

            ChatInfo(
                id: 492,
                contactJid: "34622646182@s.whatsapp.net",
                name: "Jose Luis Vicedo",
                numberMessages: 41,
                lastMessageDate: dateFormatter.date(from: "2023-12-18 09:28:37")!,
                isArchived: false            ),

            ChatInfo(
                id: 543,
                contactJid: "34620617398@s.whatsapp.net",
                name: "Pierre",
                numberMessages: 31,
                lastMessageDate: dateFormatter.date(from: "2023-12-01 10:56:39")!,
                isArchived: false            ),

            ChatInfo(
                id: 592,
                contactJid: "34658205668@s.whatsapp.net",
                name: "Mábel",
                numberMessages: 14,
                lastMessageDate: dateFormatter.date(from: "2023-11-16 20:01:25")!,
                isArchived: false            ),

            ChatInfo(
                id: 53,
                contactJid: "34652621675@s.whatsapp.net",
                name: "Cristina",
                numberMessages: 244,
                lastMessageDate: dateFormatter.date(from: "2023-11-15 08:22:54")!,
                isArchived: false            ),

            ChatInfo(
                id: 590,
                contactJid: "34620172662@s.whatsapp.net",
                name: "Carmen 💍",
                numberMessages: 6,
                lastMessageDate: dateFormatter.date(from: "2023-11-12 00:42:16")!,
                isArchived: false            ),

            ChatInfo(
                id: 589,
                contactJid: "34674264300@s.whatsapp.net",
                name: "Ana Ruiz - Compañera Piso Lucia",
                numberMessages: 23,
                lastMessageDate: dateFormatter.date(from: "2023-11-12 00:35:29")!,
                isArchived: false            ),

            ChatInfo(
                id: 588,
                contactJid: "34606170479@s.whatsapp.net",
                name: "Ismael - Amigo Lucía",
                numberMessages: 32,
                lastMessageDate: dateFormatter.date(from: "2023-11-12 00:25:53")!,
                isArchived: false            ),

            ChatInfo(
                id: 256,
                contactJid: "34638101004@s.whatsapp.net",
                name: "+34 638 10 10 04",
                numberMessages: 263,
                lastMessageDate: dateFormatter.date(from: "2023-11-07 14:26:46")!,
                isArchived: false            ),

            ChatInfo(
                id: 581,
                contactJid: "34659219578@s.whatsapp.net",
                name: "Jose Maria Primo",
                numberMessages: 24,
                lastMessageDate: dateFormatter.date(from: "2023-10-05 18:40:08")!,
                isArchived: false            ),

            ChatInfo(
                id: 561,
                contactJid: "34973901871@s.whatsapp.net",
                name: "+34 973 90 18 71",
                numberMessages: 16,
                lastMessageDate: dateFormatter.date(from: "2023-09-22 11:29:46")!,
                isArchived: false            ),

            ChatInfo(
                id: 99,
                contactJid: "34665339124@s.whatsapp.net",
                name: "Marisa",
                numberMessages: 65,
                lastMessageDate: dateFormatter.date(from: "2023-09-01 21:01:34")!,
                isArchived: false            ),

            ChatInfo(
                id: 579,
                contactJid: "34616203656@s.whatsapp.net",
                name: "+34 616 20 36 56",
                numberMessages: 21,
                lastMessageDate: dateFormatter.date(from: "2023-08-10 13:42:02")!,
                isArchived: false            ),

            ChatInfo(
                id: 6,
                contactJid: "34693330041@s.whatsapp.net",
                name: "Carlos",
                numberMessages: 423,
                lastMessageDate: dateFormatter.date(from: "2023-07-14 21:53:51")!,
                isArchived: false            ),

            ChatInfo(
                id: 92,
                contactJid: "34606287943@s.whatsapp.net",
                name: "Muñaqui",
                numberMessages: 79,
                lastMessageDate: dateFormatter.date(from: "2023-06-26 19:56:47")!,
                isArchived: false            ),

            ChatInfo(
                id: 157,
                contactJid: "34677819474@s.whatsapp.net",
                name: "Fran García",
                numberMessages: 153,
                lastMessageDate: dateFormatter.date(from: "2023-05-10 14:02:43")!,
                isArchived: false            ),

            ChatInfo(
                id: 131,
                contactJid: "34676613101@s.whatsapp.net",
                name: "Fernando Padre Gorka",
                numberMessages: 57,
                lastMessageDate: dateFormatter.date(from: "2023-03-03 12:05:36")!,
                isArchived: false            ),

            ChatInfo(
                id: 556,
                contactJid: "34666551935@s.whatsapp.net",
                name: "Angelín",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2023-02-28 12:06:30")!,
                isArchived: false            ),

            ChatInfo(
                id: 54,
                contactJid: "34626785395@s.whatsapp.net",
                name: "Otto",
                numberMessages: 111,
                lastMessageDate: dateFormatter.date(from: "2023-02-17 19:49:58")!,
                isArchived: false            ),

            ChatInfo(
                id: 466,
                contactJid: "34911650148@s.whatsapp.net",
                name: "+34 911 65 01 48",
                numberMessages: 12,
                lastMessageDate: dateFormatter.date(from: "2023-02-17 10:34:34")!,
                isArchived: false            ),

            ChatInfo(
                id: 171,
                contactJid: "34685431434@s.whatsapp.net",
                name: "+34 685 43 14 34",
                numberMessages: 69,
                lastMessageDate: dateFormatter.date(from: "2023-01-10 15:52:51")!,
                isArchived: false            ),

            ChatInfo(
                id: 517,
                contactJid: "34654734438@s.whatsapp.net",
                name: "+34 654 73 44 38",
                numberMessages: 14,
                lastMessageDate: dateFormatter.date(from: "2022-12-22 12:53:07")!,
                isArchived: false            ),

            ChatInfo(
                id: 498,
                contactJid: "34640807427@s.whatsapp.net",
                name: "+34 640 80 74 27",
                numberMessages: 8,
                lastMessageDate: dateFormatter.date(from: "2022-12-21 09:16:33")!,
                isArchived: false            ),

            ChatInfo(
                id: 116,
                contactJid: "34648936892@s.whatsapp.net",
                name: "Hugo",
                numberMessages: 159,
                lastMessageDate: dateFormatter.date(from: "2022-12-15 12:38:38")!,
                isArchived: false            ),

            ChatInfo(
                id: 18,
                contactJid: "34662004274@s.whatsapp.net",
                name: "Miguel Cazorla",
                numberMessages: 130,
                lastMessageDate: dateFormatter.date(from: "2022-12-08 22:32:18")!,
                isArchived: false            ),

            ChatInfo(
                id: 93,
                contactJid: "34647719094@s.whatsapp.net",
                name: "Elisa",
                numberMessages: 79,
                lastMessageDate: dateFormatter.date(from: "2022-11-03 14:36:46")!,
                isArchived: false            ),

            ChatInfo(
                id: 59,
                contactJid: "34636885959@s.whatsapp.net",
                name: "Maite",
                numberMessages: 27,
                lastMessageDate: dateFormatter.date(from: "2022-10-16 12:33:27")!,
                isArchived: false            ),

            ChatInfo(
                id: 458,
                contactJid: "34670086411@s.whatsapp.net",
                name: "+34 670 08 64 11",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2022-09-18 12:24:48")!,
                isArchived: false            ),

            ChatInfo(
                id: 457,
                contactJid: "34671246793@s.whatsapp.net",
                name: "+34 671 24 67 93",
                numberMessages: 13,
                lastMessageDate: dateFormatter.date(from: "2022-09-13 09:32:22")!,
                isArchived: false            ),

            ChatInfo(
                id: 448,
                contactJid: "393355770107@s.whatsapp.net",
                name: "+39 335 577 0107",
                numberMessages: 10,
                lastMessageDate: dateFormatter.date(from: "2022-08-25 10:19:10")!,
                isArchived: false            ),

            ChatInfo(
                id: 435,
                contactJid: "120363044545720321@g.us",
                name: "Cumple MARI TRINI REGALO",
                numberMessages: 476,
                lastMessageDate: dateFormatter.date(from: "2022-08-01 20:21:19")!,
                isArchived: false            ),

            ChatInfo(
                id: 32,
                contactJid: "34670528038@s.whatsapp.net",
                name: "Paco Moreno",
                numberMessages: 60,
                lastMessageDate: dateFormatter.date(from: "2022-07-22 12:11:06")!,
                isArchived: false            ),

            ChatInfo(
                id: 302,
                contactJid: "34689021600@s.whatsapp.net",
                name: "Luis",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2022-06-17 18:45:57")!,
                isArchived: false            ),

            ChatInfo(
                id: 417,
                contactJid: "34601344841@s.whatsapp.net",
                name: "Vinos y risas",
                numberMessages: 23,
                lastMessageDate: dateFormatter.date(from: "2022-06-14 12:10:21")!,
                isArchived: false            ),

            ChatInfo(
                id: 19,
                contactJid: "34665816929@s.whatsapp.net",
                name: "Alejandro Such",
                numberMessages: 180,
                lastMessageDate: dateFormatter.date(from: "2022-06-08 19:34:27")!,
                isArchived: false            ),

            ChatInfo(
                id: 361,
                contactJid: "34666837771@s.whatsapp.net",
                name: "Jorge Calvo",
                numberMessages: 89,
                lastMessageDate: dateFormatter.date(from: "2022-05-27 13:47:40")!,
                isArchived: false            ),

            ChatInfo(
                id: 391,
                contactJid: "447585174537@s.whatsapp.net",
                name: "+44 7585 174537",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2022-04-28 16:48:26")!,
                isArchived: true            ),

            ChatInfo(
                id: 376,
                contactJid: "34672351765-1490792654@g.us",
                name: "Vigilancia PPSS",
                numberMessages: 103,
                lastMessageDate: dateFormatter.date(from: "2022-03-24 12:26:53")!,
                isArchived: false            ),

            ChatInfo(
                id: 339,
                contactJid: "34670103554@s.whatsapp.net",
                name: "+34 670 10 35 54",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2022-02-01 14:19:45")!,
                isArchived: false            ),

            ChatInfo(
                id: 365,
                contactJid: "120363036963223997@g.us",
                name: "OICV Alicante",
                numberMessages: 382,
                lastMessageDate: dateFormatter.date(from: "2022-01-28 14:58:58")!,
                isArchived: false            ),

            ChatInfo(
                id: 133,
                contactJid: "34630155981@s.whatsapp.net",
                name: "Elías - Elena",
                numberMessages: 28,
                lastMessageDate: dateFormatter.date(from: "2022-01-11 12:29:40")!,
                isArchived: false            ),

            ChatInfo(
                id: 342,
                contactJid: "34636680185@s.whatsapp.net",
                name: "La Pequeña Bodeguita",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2021-12-24 18:56:58")!,
                isArchived: false            ),

            ChatInfo(
                id: 327,
                contactJid: "34607729677@s.whatsapp.net",
                name: "+34 607 72 96 77",
                numberMessages: 6,
                lastMessageDate: dateFormatter.date(from: "2021-12-02 12:27:40")!,
                isArchived: false            ),

            ChatInfo(
                id: 316,
                contactJid: "34617664920@s.whatsapp.net",
                name: "Jose Luis Vecino",
                numberMessages: 8,
                lastMessageDate: dateFormatter.date(from: "2021-12-01 17:18:01")!,
                isArchived: false            ),

            ChatInfo(
                id: 299,
                contactJid: "34655784262-1634044334@g.us",
                name: "Cumpleaños de Juan",
                numberMessages: 16,
                lastMessageDate: dateFormatter.date(from: "2021-10-13 22:08:48")!,
                isArchived: false            ),

            ChatInfo(
                id: 263,
                contactJid: "34658805146@s.whatsapp.net",
                name: "Libreria Valencia",
                numberMessages: 24,
                lastMessageDate: dateFormatter.date(from: "2021-09-01 20:28:18")!,
                isArchived: false            ),

            ChatInfo(
                id: 225,
                contactJid: "34670528038-1412460666@g.us",
                name: "Llepaplats",
                numberMessages: 830,
                lastMessageDate: dateFormatter.date(from: "2021-08-14 15:27:36")!,
                isArchived: false            ),

            ChatInfo(
                id: 21,
                contactJid: "34652197580@s.whatsapp.net",
                name: "Mari Trini",
                numberMessages: 45,
                lastMessageDate: dateFormatter.date(from: "2021-08-08 10:04:44")!,
                isArchived: false            ),

            ChatInfo(
                id: 212,
                contactJid: "34646769232@s.whatsapp.net",
                name: "Piedad",
                numberMessages: 12,
                lastMessageDate: dateFormatter.date(from: "2021-08-04 18:51:27")!,
                isArchived: false            ),

            ChatInfo(
                id: 254,
                contactJid: "34618585721@s.whatsapp.net",
                name: "+34 618 58 57 21",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2021-04-22 15:42:58")!,
                isArchived: false            ),

            ChatInfo(
                id: 251,
                contactJid: "34616145202@s.whatsapp.net",
                name: "Sonia Informatica",
                numberMessages: 9,
                lastMessageDate: dateFormatter.date(from: "2021-03-26 13:11:41")!,
                isArchived: false            ),

            ChatInfo(
                id: 110,
                contactJid: "34670528038-1474731097@g.us",
                name: "Furbolín",
                numberMessages: 698,
                lastMessageDate: dateFormatter.date(from: "2021-01-31 18:38:39")!,
                isArchived: false            ),

            ChatInfo(
                id: 211,
                contactJid: "34635672302@s.whatsapp.net",
                name: "+34 635 67 23 02",
                numberMessages: 29,
                lastMessageDate: dateFormatter.date(from: "2021-01-29 11:09:10")!,
                isArchived: false            ),

            ChatInfo(
                id: 229,
                contactJid: "34672351765-1604417953@g.us",
                name: "Vigilancia PA",
                numberMessages: 101,
                lastMessageDate: dateFormatter.date(from: "2021-01-28 09:13:53")!,
                isArchived: false            ),

            ChatInfo(
                id: 249,
                contactJid: "34665166632@s.whatsapp.net",
                name: "Dato",
                numberMessages: 16,
                lastMessageDate: dateFormatter.date(from: "2021-01-24 09:10:59")!,
                isArchived: false            ),

            ChatInfo(
                id: 87,
                contactJid: "34649254458@s.whatsapp.net",
                name: "Mercedes",
                numberMessages: 92,
                lastMessageDate: dateFormatter.date(from: "2021-01-01 12:24:41")!,
                isArchived: false            ),

            ChatInfo(
                id: 230,
                contactJid: "34693206402-1607973235@g.us",
                name: "Regalo de navidad de mamá",
                numberMessages: 29,
                lastMessageDate: dateFormatter.date(from: "2020-12-19 13:43:17")!,
                isArchived: false            ),

            ChatInfo(
                id: 114,
                contactJid: "34633285989@s.whatsapp.net",
                name: "Diego",
                numberMessages: 191,
                lastMessageDate: dateFormatter.date(from: "2020-09-24 19:17:25")!,
                isArchived: false            ),

            ChatInfo(
                id: 222,
                contactJid: "34634490736@s.whatsapp.net",
                name: "+34 634 49 07 36",
                numberMessages: 9,
                lastMessageDate: dateFormatter.date(from: "2020-07-10 12:25:21")!,
                isArchived: false            ),

            ChatInfo(
                id: 221,
                contactJid: "34670925836@s.whatsapp.net",
                name: "+34 670 92 58 36",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2020-06-29 17:43:03")!,
                isArchived: true            ),

            ChatInfo(
                id: 214,
                contactJid: "5491123922291@s.whatsapp.net",
                name: "+54 9 11 2392-2291",
                numberMessages: 13,
                lastMessageDate: dateFormatter.date(from: "2020-02-18 14:47:42")!,
                isArchived: false            ),

            ChatInfo(
                id: 213,
                contactJid: "34610787322@s.whatsapp.net",
                name: "+34 610 78 73 22",
                numberMessages: 10,
                lastMessageDate: dateFormatter.date(from: "2020-01-15 20:56:02")!,
                isArchived: true            ),

            ChatInfo(
                id: 172,
                contactJid: "34654638410-1545999508@g.us",
                name: "Cena Nochevieja general 😜",
                numberMessages: 149,
                lastMessageDate: dateFormatter.date(from: "2020-01-05 19:00:45")!,
                isArchived: false            ),

            ChatInfo(
                id: 57,
                contactJid: "34646694303@s.whatsapp.net",
                name: "Jose Antonio Belda",
                numberMessages: 25,
                lastMessageDate: dateFormatter.date(from: "2019-10-18 18:31:25")!,
                isArchived: false            ),

            ChatInfo(
                id: 17,
                contactJid: "34606537761@s.whatsapp.net",
                name: "Clara - Sara",
                numberMessages: 27,
                lastMessageDate: dateFormatter.date(from: "2019-09-21 00:45:53")!,
                isArchived: false            ),

            ChatInfo(
                id: 206,
                contactJid: "34691598733@s.whatsapp.net",
                name: "Recogidas Reto",
                numberMessages: 24,
                lastMessageDate: dateFormatter.date(from: "2019-09-19 15:01:37")!,
                isArchived: false            ),

            ChatInfo(
                id: 155,
                contactJid: "34654011839@s.whatsapp.net",
                name: "+34 654 01 18 39",
                numberMessages: 16,
                lastMessageDate: dateFormatter.date(from: "2019-09-06 08:18:13")!,
                isArchived: false            ),

            ChatInfo(
                id: 204,
                contactJid: "34673006909@s.whatsapp.net",
                name: "Casa Rural León",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2019-08-16 15:49:52")!,
                isArchived: false            ),

            ChatInfo(
                id: 185,
                contactJid: "34686037437@s.whatsapp.net",
                name: "Apartamento Ponferrada",
                numberMessages: 34,
                lastMessageDate: dateFormatter.date(from: "2019-08-16 09:43:05")!,
                isArchived: false            ),

            ChatInfo(
                id: 203,
                contactJid: "34692211619@s.whatsapp.net",
                name: "Fernando - Taller",
                numberMessages: 2,
                lastMessageDate: dateFormatter.date(from: "2019-08-05 19:06:27")!,
                isArchived: false            ),

            ChatInfo(
                id: 202,
                contactJid: "593987222270@s.whatsapp.net",
                name: "+593 98 722 2270",
                numberMessages: 9,
                lastMessageDate: dateFormatter.date(from: "2019-08-04 23:46:08")!,
                isArchived: false            ),

            ChatInfo(
                id: 35,
                contactJid: "34633121331@s.whatsapp.net",
                name: "Manri",
                numberMessages: 42,
                lastMessageDate: dateFormatter.date(from: "2019-07-22 20:44:22")!,
                isArchived: false            ),

            ChatInfo(
                id: 199,
                contactJid: "34699074946@s.whatsapp.net",
                name: "Jesús",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2019-07-07 20:02:02")!,
                isArchived: false            ),

            ChatInfo(
                id: 45,
                contactJid: "34660404913@s.whatsapp.net",
                name: "+34 660 40 49 13",
                numberMessages: 15,
                lastMessageDate: dateFormatter.date(from: "2019-07-07 19:31:41")!,
                isArchived: false            ),

            ChatInfo(
                id: 189,
                contactJid: "34655547719@s.whatsapp.net",
                name: "Juan Gabriel",
                numberMessages: 10,
                lastMessageDate: dateFormatter.date(from: "2019-05-14 20:53:05")!,
                isArchived: false            ),

            ChatInfo(
                id: 188,
                contactJid: "34607462377@s.whatsapp.net",
                name: "Cristobal Infantes",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2019-05-13 19:07:25")!,
                isArchived: false            ),

            ChatInfo(
                id: 184,
                contactJid: "34667527531@s.whatsapp.net",
                name: "Casa Rural Valdepielago",
                numberMessages: 6,
                lastMessageDate: dateFormatter.date(from: "2019-05-02 13:38:46")!,
                isArchived: false            ),

            ChatInfo(
                id: 183,
                contactJid: "34638703982@s.whatsapp.net",
                name: "+34 638 70 39 82",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2019-04-18 13:09:46")!,
                isArchived: false            ),

            ChatInfo(
                id: 175,
                contactJid: "34655280429@s.whatsapp.net",
                name: "Fisioterapia María Monpó",
                numberMessages: 10,
                lastMessageDate: dateFormatter.date(from: "2019-02-06 12:04:13")!,
                isArchived: false            ),

            ChatInfo(
                id: 111,
                contactJid: "34600012880@s.whatsapp.net",
                name: "Vicente amigo Lucía",
                numberMessages: 11,
                lastMessageDate: dateFormatter.date(from: "2018-12-26 21:28:23")!,
                isArchived: false            ),

            ChatInfo(
                id: 148,
                contactJid: "34655157634@s.whatsapp.net",
                name: "Raquel - Alicia",
                numberMessages: 20,
                lastMessageDate: dateFormatter.date(from: "2018-12-08 11:36:49")!,
                isArchived: false            ),

            ChatInfo(
                id: 169,
                contactJid: "34681649028@s.whatsapp.net",
                name: "+34 681 64 90 28",
                numberMessages: 2,
                lastMessageDate: dateFormatter.date(from: "2018-11-29 18:13:05")!,
                isArchived: false            ),

            ChatInfo(
                id: 168,
                contactJid: "34671964643@s.whatsapp.net",
                name: "Miriam Amiga Lucía",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2018-11-28 09:51:01")!,
                isArchived: false            ),

            ChatInfo(
                id: 154,
                contactJid: "34638748818@s.whatsapp.net",
                name: "+34 638 74 88 18",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2018-08-31 09:36:45")!,
                isArchived: false            ),

            ChatInfo(
                id: 149,
                contactJid: "34652621675-1531292568@g.us",
                name: "Canadá",
                numberMessages: 46,
                lastMessageDate: dateFormatter.date(from: "2018-08-06 11:59:50")!,
                isArchived: false            ),

            ChatInfo(
                id: 142,
                contactJid: "34637629196@s.whatsapp.net",
                name: "Guillermo Primo",
                numberMessages: 60,
                lastMessageDate: dateFormatter.date(from: "2018-07-23 18:21:37")!,
                isArchived: false            ),

            ChatInfo(
                id: 146,
                contactJid: "34652621675-1526737884@g.us",
                name: "Comunión de Pablo 2-6-18",
                numberMessages: 144,
                lastMessageDate: dateFormatter.date(from: "2018-06-03 18:11:03")!,
                isArchived: false            ),

            ChatInfo(
                id: 145,
                contactJid: "34626066529@s.whatsapp.net",
                name: "+34 626 06 65 29",
                numberMessages: 5,
                lastMessageDate: dateFormatter.date(from: "2018-04-03 11:54:56")!,
                isArchived: false            ),

            ChatInfo(
                id: 144,
                contactJid: "34615457428@s.whatsapp.net",
                name: "+34 615 45 74 28",
                numberMessages: 9,
                lastMessageDate: dateFormatter.date(from: "2018-04-01 12:09:37")!,
                isArchived: false            ),

            ChatInfo(
                id: 132,
                contactJid: "34687905973@s.whatsapp.net",
                name: "+34 687 90 59 73",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2018-03-09 22:04:24")!,
                isArchived: false            ),

            ChatInfo(
                id: 140,
                contactJid: "34658659515@s.whatsapp.net",
                name: "Jose Luis Zamora",
                numberMessages: 22,
                lastMessageDate: dateFormatter.date(from: "2018-03-01 19:18:45")!,
                isArchived: false            ),

            ChatInfo(
                id: 129,
                contactJid: "34681241899@s.whatsapp.net",
                name: "Felipe",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2017-12-31 15:40:38")!,
                isArchived: false            ),

            ChatInfo(
                id: 127,
                contactJid: "34665497594@s.whatsapp.net",
                name: "Alfons Delaxarxa",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2017-02-27 21:33:47")!,
                isArchived: false            ),

            ChatInfo(
                id: 119,
                contactJid: "34615203128@s.whatsapp.net",
                name: "+34 615 20 31 28",
                numberMessages: 10,
                lastMessageDate: dateFormatter.date(from: "2017-02-11 16:06:19")!,
                isArchived: true            ),

            ChatInfo(
                id: 118,
                contactJid: "34655967776@s.whatsapp.net",
                name: "+34 655 96 77 76",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2017-01-07 21:26:44")!,
                isArchived: false            ),

            ChatInfo(
                id: 112,
                contactJid: "34663024302@s.whatsapp.net",
                name: "Jose amigo Lucía",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2016-12-03 21:06:50")!,
                isArchived: false            ),

            ChatInfo(
                id: 16,
                contactJid: "34601279318@s.whatsapp.net",
                name: "+34 601 27 93 18",
                numberMessages: 99,
                lastMessageDate: dateFormatter.date(from: "2016-12-03 20:25:18")!,
                isArchived: false            ),

            ChatInfo(
                id: 109,
                contactJid: "34608230523@s.whatsapp.net",
                name: "Ana Prima",
                numberMessages: 12,
                lastMessageDate: dateFormatter.date(from: "2016-08-27 10:25:48")!,
                isArchived: false            ),

            ChatInfo(
                id: 5,
                contactJid: "447707711196@s.whatsapp.net",
                name: "Fran García",
                numberMessages: 88,
                lastMessageDate: dateFormatter.date(from: "2016-08-05 17:30:18")!,
                isArchived: false            ),

            ChatInfo(
                id: 104,
                contactJid: "34600512930@s.whatsapp.net",
                name: "+34 600 51 29 30",
                numberMessages: 21,
                lastMessageDate: dateFormatter.date(from: "2016-08-03 20:08:11")!,
                isArchived: false            ),

            ChatInfo(
                id: 102,
                contactJid: "34670768209@s.whatsapp.net",
                name: "Miguel Angel",
                numberMessages: 3,
                lastMessageDate: dateFormatter.date(from: "2016-06-26 12:40:55")!,
                isArchived: false            ),

            ChatInfo(
                id: 98,
                contactJid: "34654793120@s.whatsapp.net",
                name: "+34 654 79 31 20",
                numberMessages: 17,
                lastMessageDate: dateFormatter.date(from: "2016-05-27 20:58:34")!,
                isArchived: false            ),

            ChatInfo(
                id: 83,
                contactJid: "34660709316@s.whatsapp.net",
                name: "+34 660 70 93 16",
                numberMessages: 77,
                lastMessageDate: dateFormatter.date(from: "2016-05-26 20:06:33")!,
                isArchived: false            ),

            ChatInfo(
                id: 55,
                contactJid: "34666551935-1419436152@g.us",
                name: "Los Lopez - primos ",
                numberMessages: 106,
                lastMessageDate: dateFormatter.date(from: "2016-05-01 02:02:34")!,
                isArchived: false            ),

            ChatInfo(
                id: 94,
                contactJid: "34675206121@s.whatsapp.net",
                name: "María Prima",
                numberMessages: 18,
                lastMessageDate: dateFormatter.date(from: "2016-04-22 13:17:59")!,
                isArchived: false            ),

            ChatInfo(
                id: 96,
                contactJid: "34655445043-1460353359@g.us",
                name: "Perugia",
                numberMessages: 126,
                lastMessageDate: dateFormatter.date(from: "2016-04-15 23:05:30")!,
                isArchived: false            ),

            ChatInfo(
                id: 95,
                contactJid: "34609436010@s.whatsapp.net",
                name: "+34 609 43 60 10",
                numberMessages: 2,
                lastMessageDate: dateFormatter.date(from: "2016-04-01 22:11:12")!,
                isArchived: false            ),

            ChatInfo(
                id: 40,
                contactJid: "34686489843@s.whatsapp.net",
                name: "Jose Bonora",
                numberMessages: 34,
                lastMessageDate: dateFormatter.date(from: "2015-07-23 22:47:27")!,
                isArchived: false            ),

            ChatInfo(
                id: 68,
                contactJid: "34644407559@s.whatsapp.net",
                name: "+34 644 40 75 59",
                numberMessages: 33,
                lastMessageDate: dateFormatter.date(from: "2015-06-20 20:25:02")!,
                isArchived: false            ),

            ChatInfo(
                id: 30,
                contactJid: "34619812911@s.whatsapp.net",
                name: "Pilar - Lucía López",
                numberMessages: 30,
                lastMessageDate: dateFormatter.date(from: "2015-06-20 19:55:28")!,
                isArchived: false            ),

            ChatInfo(
                id: 81,
                contactJid: "34607371932@s.whatsapp.net",
                name: "+34 607 37 19 32",
                numberMessages: 19,
                lastMessageDate: dateFormatter.date(from: "2015-06-15 12:23:07")!,
                isArchived: false            ),

            ChatInfo(
                id: 27,
                contactJid: "34691991253@s.whatsapp.net",
                name: "+34 691 99 12 53",
                numberMessages: 146,
                lastMessageDate: dateFormatter.date(from: "2015-05-28 23:58:35")!,
                isArchived: false            ),

            ChatInfo(
                id: 67,
                contactJid: "34650563256@s.whatsapp.net",
                name: "+34 650 56 32 56",
                numberMessages: 6,
                lastMessageDate: dateFormatter.date(from: "2015-02-23 09:24:12")!,
                isArchived: false            ),

            ChatInfo(
                id: 65,
                contactJid: "34689256819@s.whatsapp.net",
                name: "+34 689 25 68 19",
                numberMessages: 8,
                lastMessageDate: dateFormatter.date(from: "2015-02-15 02:25:40")!,
                isArchived: false            ),

            ChatInfo(
                id: 61,
                contactJid: "34643303404@s.whatsapp.net",
                name: "+34 643 30 34 04",
                numberMessages: 25,
                lastMessageDate: dateFormatter.date(from: "2015-02-11 14:54:18")!,
                isArchived: false            ),

            ChatInfo(
                id: 64,
                contactJid: "34603698420@s.whatsapp.net",
                name: "+34 603 69 84 20",
                numberMessages: 63,
                lastMessageDate: dateFormatter.date(from: "2015-02-10 17:08:57")!,
                isArchived: false            ),

            ChatInfo(
                id: 63,
                contactJid: "34667431254@s.whatsapp.net",
                name: "+34 667 43 12 54",
                numberMessages: 12,
                lastMessageDate: dateFormatter.date(from: "2015-02-10 00:03:04")!,
                isArchived: false            ),

            ChatInfo(
                id: 60,
                contactJid: "34665497594-1421237760@g.us",
                name: "Muerte del padre de Luis",
                numberMessages: 19,
                lastMessageDate: dateFormatter.date(from: "2015-01-15 11:40:44")!,
                isArchived: false            ),

            ChatInfo(
                id: 49,
                contactJid: "34676534061@s.whatsapp.net",
                name: "+34 676 53 40 61",
                numberMessages: 10,
                lastMessageDate: dateFormatter.date(from: "2014-11-20 14:44:59")!,
                isArchived: false            ),

            ChatInfo(
                id: 48,
                contactJid: "34663390806@s.whatsapp.net",
                name: "+34 663 39 08 06",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2014-11-13 10:51:24")!,
                isArchived: false            ),

            ChatInfo(
                id: 47,
                contactJid: "34609583390@s.whatsapp.net",
                name: "+34 609 58 33 90",
                numberMessages: 9,
                lastMessageDate: dateFormatter.date(from: "2014-10-10 15:47:48")!,
                isArchived: false            ),

            ChatInfo(
                id: 41,
                contactJid: "34657468850@s.whatsapp.net",
                name: "+34 657 46 88 50",
                numberMessages: 25,
                lastMessageDate: dateFormatter.date(from: "2014-07-11 23:34:13")!,
                isArchived: false            ),

            ChatInfo(
                id: 37,
                contactJid: "34655445043@s.whatsapp.net",
                name: "+34 655 44 50 43",
                numberMessages: 2,
                lastMessageDate: dateFormatter.date(from: "2014-06-16 17:00:42")!,
                isArchived: false            ),

            ChatInfo(
                id: 33,
                contactJid: "34600869907@s.whatsapp.net",
                name: "+34 600 86 99 07",
                numberMessages: 18,
                lastMessageDate: dateFormatter.date(from: "2014-04-27 18:11:35")!,
                isArchived: false            ),

            ChatInfo(
                id: 25,
                contactJid: "34605367031@s.whatsapp.net",
                name: "Sonia - Berta",
                numberMessages: 4,
                lastMessageDate: dateFormatter.date(from: "2013-12-06 04:12:08")!,
                isArchived: false
            ),

        ]
        
        do {
            let backups = try waBackup.getBackups()
            guard let iPhoneBackup = backups.validBackups.first else {
                XCTFail("No se encontraron backups válidos")
                return
            }
            try waBackup.connectChatStorageDb(from: iPhoneBackup)
            let chats = try waBackup.getChats()
            
            // Crear un diccionario de chats por id
            let backupChatsById = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
            let expectedChatsById = Dictionary(uniqueKeysWithValues: expectedChats.map { ($0.id, $0) })
            
            for (id, expectedChat) in expectedChatsById {
                if let backupChat = backupChatsById[id] {
                    // Comparar número de mensajes
                    if backupChat.numberMessages != expectedChat.numberMessages {
                        XCTFail("Chat id \(id) (\(expectedChat.name)): se esperaban \(expectedChat.numberMessages) mensajes, se encontraron \(backupChat.numberMessages)")
                    }
                } else {
                    XCTFail("No se encontró el chat esperado con id \(id) (\(expectedChat.name)) en el backup")
                }
            }
            
            // Verificar si hay chats extra en el backup que no se esperaban
            let extraChatIds = Set(backupChatsById.keys).subtracting(expectedChatsById.keys)
            if !extraChatIds.isEmpty {
                let extraChats = extraChatIds.compactMap { backupChatsById[$0]?.name }
                XCTFail("Se encontraron chats extra en el backup que no se esperaban: \(extraChats)")
            }
        } catch {
            XCTFail("Error al obtener los chats: \(error)")
        }
    }
    
    func testChatMessages() throws {
        let testBackupPath = TestSupport.fixtureRoot.path
        let waBackup = WABackup(backupPath: testBackupPath)
        do {
            let backups = try waBackup.getBackups()
            guard let iPhoneBackup = backups.validBackups.first else {
                XCTFail("No valid backups found")
                return
            }
            try waBackup.connectChatStorageDb(from: iPhoneBackup)
            let chats = try waBackup.getChats()
            
            // Initialize counts
            var messageTypeCounts: [String: Int] = [:]
            var totalMessages = 0
            
            for chat in chats {
                let chatDump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: nil)
                let messages = chatDump.messages
                XCTAssertEqual(messages.count, chat.numberMessages, "Incorrect number of messages in chat ID \(chat.id)")
                
                totalMessages += messages.count
                
                // Process messages
                for message in messages {
                    let messageType = message.messageType
                    messageTypeCounts[messageType, default: 0] += 1
                }
            }
            
            XCTAssertEqual(totalMessages, 85831, "Incorrect number of messages")
            
            // Expected quantities (replace these with your actual expected values)
            let expectedCounts: [String: Int] = [
                "Text": 73617,
                "Image": 5281,
                "Video": 489,
                "Audio": 4942,
                "Contact": 32,
                "Location": 51,
                "Link": 754,
                "Document": 144,
                "Status": 264,
                "GIF": 46,
                "Sticker": 211
            ]
            
            // Check counts against expected quantities
            for (messageType, expectedCount) in expectedCounts {
                let actualCount = messageTypeCounts[messageType] ?? 0
                XCTAssertEqual(actualCount, expectedCount, "Incorrect number of \(messageType) messages")
            }
            
        } catch {
            XCTFail("Error retrieving messages: \(error)")
        }
    }
    
    func testChatContacts() throws {
        let testBackupPath = TestSupport.fixtureRoot.path
        let waBackup = WABackup(backupPath: testBackupPath)
        
        do {
            let backups = try waBackup.getBackups()
            guard let iPhoneBackup = backups.validBackups.first else {
                XCTFail("No valid backups found")
                return
            }
            try waBackup.connectChatStorageDb(from: iPhoneBackup)
            let chats = try waBackup.getChats()
            
            // Crear directorio temporal para imágenes de contacto
            let fileManager = FileManager.default
            let tmpDir = fileManager.temporaryDirectory.appendingPathComponent("ContactImages", isDirectory: true)
            if !fileManager.fileExists(atPath: tmpDir.path) {
                try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            }

            var allContacts: Set<ContactInfo> = []

            for chat in chats {
                let chatDump = try waBackup.getChat(chatId: chat.id, directoryToSaveMedia: tmpDir)
                let contacts = chatDump.contacts
                allContacts.formUnion(contacts)
            }

            let contactsWithImage = allContacts.filter { $0.photoFilename != nil }
            let contactsWithoutImage = allContacts.filter { $0.photoFilename == nil }

            // Aserciones del test
            XCTAssertEqual(chats.count, 181, "Número de chats distinto del esperado")
            XCTAssertEqual(allContacts.count, 225, "Número de contactos únicos distinto del esperado")
            XCTAssertEqual(contactsWithImage.count, 192, "Número de contactos con imagen distinto del esperado")
            XCTAssertEqual(contactsWithoutImage.count, 33, "Número de contactos sin imagen distinto del esperado")

            // Limpieza
            try fileManager.removeItem(at: tmpDir)

        } catch {
            XCTFail("Error retrieving contacts: \(error)")
        }
    }
    
    func testMessageContentExtraction() throws {
        let testBackupPath = TestSupport.fixtureRoot.path
        let waBackup = WABackup(backupPath: testBackupPath)
        
        do {
            let backups = try waBackup.getBackups()
            guard let iPhoneBackup = backups.validBackups.first else {
                XCTFail("No valid backups found")
                return
            }
            try waBackup.connectChatStorageDb(from: iPhoneBackup)
            let chatDump = try waBackup.getChat(chatId: 44, directoryToSaveMedia: nil)
            let messages = chatDump.messages
            
            let expectedMessages: [ExpectedMessage] = [
                ExpectedMessage(
                    id: 131767,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Claro!!! Habrá más cafés y comidas 😄👍👍",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 131764,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Un placer, Domingo. Ha sido un lujo trabajar contigo , y siempre estaré en deuda contigo. \nY no es un adiós ni mucho menos. Ahora que tienes más tiempo podrás organizar más comidas, cafés o lo que se tercie.",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 131730,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Michas gracias por todo otra vez, ha sido una pasada 😄🙌🙌",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 131729,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Buenas Aitor, ya me he descargado lo del vídeo !",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 126333,
                    chatId: 44,
                    messageType: "Link",
                    isFromMe: false,
                    message: "https://piafplara.es/?p=940",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: "Entrevista en À Punt - Proyecto de Investigación Aplicada - LARA",
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 126334,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "En la radio de Apunt ya hemos salido ;)",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 126332,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "De aquí a APunt, y después a RTVE !",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 126331,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Qué chulo !!! Estáis consiguiendo darle mucha visibilidad al proyecto 👏👏👏",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 126279,
                    chatId: 44,
                    messageType: "Document",
                    isFromMe: false,
                    message: "DIARIO INFORMACION PIA LARA.pdf",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: "fea35851-6a2c-45a3-a784-003d25576b45.pdf",
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125482,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Claro, cada vez que vaya a la UA te aviso.",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: 125479,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125487,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Jo, qué pena!",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: 125486,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125479,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Avísame también la próxima vez porfa, a ver si hay más suerte",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125485,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Una pena no poder ir !",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125478,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Y el cartel ha quedado muy bien",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125481,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Enhorabuena por el trabajo 😀👍",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125486,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Qué chulo !! Muchas gracias por avisar, pero no voy a poder... me coincide con clases",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125439,
                    chatId: 44,
                    messageType: "Image",
                    isFromMe: false,
                    message: nil,
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: "bcb30316-b72d-47a4-862e-d99c37ecb7ed.jpg",
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 125436,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Por si te interesa y estás por allí:",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119188,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Pues sí, habrá que volver al modelo antiguo",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: [Reaction(emoji: "😢", senderPhone: "34636104084")]
                ),
                ExpectedMessage(
                    id: 119187,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Me sale a cuenta comprar los libros que me vaya a leer",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119186,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Sí, carete es",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119185,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "50$ mes ...",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119184,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Es bastante caro, ya te digo",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119183,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "lo uso más que la Play, que ya es decir ;)",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119182,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Si no, me tocará pagar",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119181,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Pufff pues a ver",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119180,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Yo es que lo uso casi todos los dias ;)",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119179,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Ok. Mil gracias",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119178,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Lo pregunto el lunes y te digo algo",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119177,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Madre mía, me suena que dijeron que iban a reducir el presupuesto de la biblioteca, pero no pensé que se referían a esto 🤦‍♂️",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119176,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Ostras, también !",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119175,
                    chatId: 44,
                    messageType: "Image",
                    isFromMe: true,
                    message: nil,
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: "e92bd345-9d30-49c4-9a41-0eb1d7b4351e.jpg",
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 119173,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Hola Domingo ... puedes probar si te funciona el usuario de O'reilly? es que dice que mi cuenta ha caducado",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113948,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "OK! lo voy mirando yo también ... gracias!! 😉",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113949,
                    chatId: 44,
                    messageType: "Link",
                    isFromMe: false,
                    message: "https://squidfunk.github.io/mkdocs-material/setup/setting-up-a-blog/#rss",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: "Setting up a blog - Material for MkDocs",
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113947,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Cuando vea que soy constante, lo añadiré",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113946,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Se puede, pero no lo he puesto/probado",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: 113944,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113940,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Es que yo también quería probar algo, pero me gustaría que tuviera soporte para RSS",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113944,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "¿Tiene RSS lo de Material?",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113943,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "jajaja ese es el problema",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113938,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Tb me sirve a modo de recuerdo",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113941,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Gracias! A ver si no desfallezco y escribo al menos una vez al mes",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113942,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Y muy chulo tu blog :)",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113945,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Lo miro y ya te digo algo !",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113939,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Pues sí, es una buena idea",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113928,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "y ahí meterlo todo",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113931,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Un GitHub del expertojavaua",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113930,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Es otra posibilidad",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113937,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Sí, es verdad !",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113929,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "En GitHub",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113935,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "¿Tú donde tienes tus apuntes?",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113932,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "No, del departamento",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113936,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "alguno de la eps",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113934,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "jajajaj por eso te pregunto",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113933,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Pero yo creo que sí",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113919,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Ese es otro tema, que aquí cada vez están cerrando más lo de los servidores y tendría que \"negociarlo\"",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113925,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Tenéis un servidor web donde os dejen publicarlos?",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113921,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Pero como ahora estaban todos abiertos habría que repasar las URLs y ya está",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113923,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Estaban bajo una aplicación web que hizo Miguel Ángel y que gestionaba los permisos",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113927,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Lo único informar a Google que han cambiado las direcciones",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113922,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Sí, exacto",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113924,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Como todo es estático entiendo que no será dificil",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113926,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Sí, a mi también, a ver le hecho un vistazo y miro a ver si no es muy complicado hacer una migración",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113918,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Pero me da pena que no estén",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113920,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "No, tranqui, yo ya hice mi copia y lo cogí todo … es más, los reescribí enteros con Mkdocs",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113912,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Podría buscar los HTML y pasártelos",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113916,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "¿Necesitas urgente lo de NoSQL?",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113914,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Sí, a mi me gustaría también migrarlos, aunque fuera solo el último curso",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113917,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "A mí me da pena que desaparezcan sin más",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113910,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Entonces ya son historia ? O los podemos migrar?",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113909,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Ahora hay que pensar qué hacemos",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113911,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Ostras",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113913,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Hace un par de semana que los del servicio de informática de la UA nos han obligado a cerrarlos porque no tenían el https",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113915,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Sii, se me ha pasado decíroslo",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113908,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Hola Domingo … los apuntes de expertojava.ua.es están caídos...http://expertojava.ua.es/si/nosql.html",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113176,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Una pena. Un abrazo!",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: [Reaction(emoji: "🤗", senderPhone: "Me")]
                ),
                ExpectedMessage(
                    id: 113175,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Gracias por decírmelo! A la próxima !",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113174,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Pues es una pena, pero no voy a poder ir. Precisamente los miércoles tengo toda las mañana con clase ☹️",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113173,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Hola Aitor! Gracias por comentármelo, la verdad es que no me había enterado",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113165,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Voy a intentar ir con el alumnado de IABD",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113164,
                    chatId: 44,
                    messageType: "Link",
                    isFromMe: false,
                    message: "https://www.parquecientificoumh.es/eventos/transformando-la-investigacion-e-innovacion-con-inteligencia-artificial",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: "www.parquecientificoumh.es",
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113163,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Supongo que te has enterado, pero por si acaso:",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 113162,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Hola Domingo",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109680,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Muy buena definición",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109679,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Merece la pena, no es muy caro",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109678,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Sí, exacto, es lo que era HBO al principio",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109677,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "El problema es que el catálogo no es muy extenso, pero el que hay, es bueno",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109676,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Tengo hasta el 12 de Nov la suscripción, y no descarto pagar un poco más",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109675,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Siii 👏👏",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109674,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Esta la hemos devorado mi hijo y yo ... nos ha gustado muchísimo .. tiene un gustillo a 24 brutal",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: 109673,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109673,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Y otra que podéis ver toda la familia es Secuestro en el Aire, un thriller que también te deja con ganas de ver más de un episodio seguido 😄",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109672,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Buenísima, una de espías que engancha y que se hace muy corta",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109671,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Después ya veré Slow Horses",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109670,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "😄👍👍",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109669,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Perfecto ... pues ya tenemos serie para toda la familia",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109668,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Creo que la podéis ver sin problema también con los niños",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109667,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Un Who do it muy gracioso con cada episodio contado desde un punto de vista",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109666,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Siii, es muy buena, muy graciosa",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109665,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Me alegro de lo de Bad sisters 😄",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109664,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Has visto \"Afterparty\" ? ... la recomiendan bastante.",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 109657,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Hola Domingo ... hace un par de días que acabamos \"Hermanas hasta la muerte\" y he tenido a mi mujer enganchada, que quería que cada día viéramos dos capítulos del tiróin!",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108050,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Es majo y trabajador",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108049,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Se debe de acordar de mi",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108048,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Ah, estuvo de subdirector de Informática y estuve con él un par de años preparando las olimpiadas informáticas",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108047,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Bien, a ver si conseguimos darle más visibilidad al proyecto",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108046,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Es uno de los jefazos 😄",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108045,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Cuando lo vea/hablé con él, le diré algo.",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108044,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Ha estado metido en bastantes líos directivos en la EPS",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108043,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Lo conozco de vista y de haber estado en algún tribunal de TFG",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: [Reaction(emoji: "👍", senderPhone: "34636104084")]
                ),
                ExpectedMessage(
                    id: 108041,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Es del DLSI",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108040,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Espera que lo busco",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 108039,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Otra cosa, aprovecho que te tengo por aquí. Conoces a un tal Jose Norberto de la UA?\nEs que tendré una reunión con él por un tema de datos para el proyecto Lara.",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 84001,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "👍",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 84000,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Acabo de aparcar cerca del aulario de Derecho. Voy para allá.",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83990,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Perfecto!! Nos vemos mañana 👍",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83989,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "10:30 mejor. Hay menos gente en la cafetería 😄",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83988,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Si, claro. 10:30? 11:00?",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83987,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Hola Aitor!! ¿Quedamos entonces mañana? ¿Cómo te viene?",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83380,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "😂👍🏼",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83379,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Jajaja Sí, genial. Que pena no ser jugón y no poder disfrutarlo. Ya me cuentas!! Me anoto el jueves 24 😄👍",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83378,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Así tengo más Elden Ring que contarte ;)",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83377,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Pues lo dejamos para el Jueves 24",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83376,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Pues sí, es que tengo que llevar a mi hija a Gandía, que ha quedado con unos amigos",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83375,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Lo dejamos para la otra semana, no pasa nada",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83374,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Mañana no puedo, sorry",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83373,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "¿Podrías mañana?",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83372,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Lo acabo de ver+",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83371,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Aitor!! Te acabo de enviar un correo ! Resulta que este jueves no puedo",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 83370,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Hola Domingo ... nos vemos este Jueves. Intentaré llegar sobre las 10:30 pasadas y te invito a almorzar ;)",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 41198,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Claro!!! A ver si nos vemos un día. Tenemos que quedar!",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: 41195,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 41197,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Buen viaje",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: 41193,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 41196,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Me pasaré y si veo a alguien saludo",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: 41194,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 41195,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Una pena. Me apunté ayer a última hora. A ver si nos vemos algún día, me acerco una tarde y nos tomamos un té",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 41194,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Igual está Miguel Ángel o Otto",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 41193,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Muy buenas!! Qué pena, porque hoy no he subido a la uni. Me voy a Valencia a llevarle unas cosas a Anabel ☹️☹️",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 41192,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Hey, buenos días. Esta mañana estaré por la UA con los alumnos. Estarás por el despacho a alguna hora?",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 38590,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Qué guay!! Dale recuerdos a Rubén!! Ni me acuerdo de lo del eDarling. Mi mente lo ha borrado todo 🤣",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 38589,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Estoy con Ruben Inoto. Nos ha contado que frustraste su proyecto fin de carrera de hacer un eDarling/ Tinder 😂\nOs podíais haber forrado!",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 18023,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Voy",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 18022,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Estamos en la esquina",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 18021,
                    chatId: 44,
                    messageType: "Location",
                    isFromMe: true,
                    message: nil,
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 18020,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Estoy en la calle peatonal",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 18019,
                    chatId: 44,
                    messageType: "Location",
                    isFromMe: false,
                    message: nil,
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 16987,
                    chatId: 44,
                    messageType: "Status",
                    isFromMe: false,
                    message: "Status sync from Aitor Medrano",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 9979,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Tarde. Te lo llevo el viernes?",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 9978,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "😟😟",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 9977,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "De la clase de teoría a la de práctica",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 9976,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Estoy yendo del Aulario II a la politécnica",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 9975,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Estas?",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 4474,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Qué malas son las vacaciones ;)",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 4473,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: false,
                    message: "Jajaja ya, no se ni en que día vivo ;)",
                    senderName: "Aitor Medrano",
                    senderPhone: "34636104084",
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 4472,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Te lo he dicho por el Slack, pero no sé si lo has leído",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
                ExpectedMessage(
                    id: 4471,
                    chatId: 44,
                    messageType: "Text",
                    isFromMe: true,
                    message: "Aitor, que la reunión no es mañana, es el jueves",
                    senderName: nil,
                    senderPhone: nil,
                    caption: nil,
                    mediaFilename: nil,
                    replyTo: nil,
                    reactions: nil
                ),
            ]
            
            for expectedMessage in expectedMessages {
                
                // Find the message with the expected ID
                if let actualMessage = messages.first(where: { $0.id == expectedMessage.id }) {
                    // Compare fields
                    XCTAssertEqual(actualMessage.messageType, expectedMessage.messageType, "Message type mismatch for message ID \(expectedMessage.id)")
                    XCTAssertEqual(actualMessage.isFromMe, expectedMessage.isFromMe, "isFromMe mismatch for message ID \(expectedMessage.id)")
                    XCTAssertEqual(actualMessage.message, expectedMessage.message, "Message text mismatch for message ID \(expectedMessage.id)")
                    XCTAssertEqual(actualMessage.senderName, expectedMessage.senderName, "Sender name mismatch for message ID \(expectedMessage.id)")
                    XCTAssertEqual(actualMessage.senderPhone, expectedMessage.senderPhone, "Sender phone mismatch for message ID \(expectedMessage.id)")
                    XCTAssertEqual(actualMessage.caption, expectedMessage.caption, "Caption mismatch for message ID \(expectedMessage.id)")
                    XCTAssertEqual(actualMessage.mediaFilename, expectedMessage.mediaFilename, "Media filename mismatch for message ID \(expectedMessage.id)")
                    XCTAssertEqual(actualMessage.replyTo, expectedMessage.replyTo, "ReplyTo mismatch for message ID \(expectedMessage.id)")
                    
                    // Compare reactions if applicable
                    if let expectedReactions = expectedMessage.reactions {
                        XCTAssertNotNil(actualMessage.reactions, "Reactions should not be nil for message ID \(expectedMessage.id)")
                        if let actualReactions = actualMessage.reactions {
                            XCTAssertEqual(actualReactions.count, expectedReactions.count, "Number of reactions mismatch for message ID \(expectedMessage.id)")
                            for (expectedReaction, actualReaction) in zip(expectedReactions, actualReactions) {
                                XCTAssertEqual(actualReaction.emoji, expectedReaction.emoji, "Reaction emoji mismatch for message ID \(expectedMessage.id)")
                                XCTAssertEqual(actualReaction.senderPhone, expectedReaction.senderPhone, "Reaction sender phone mismatch for message ID \(expectedMessage.id)")
                            }
                        }
                    } else {
                        XCTAssertNil(actualMessage.reactions, "Reactions should be nil for message ID \(expectedMessage.id)")
                    }
                    
                    // Add other field comparisons as needed
                } else {
                    XCTFail("Message with ID \(expectedMessage.id) not found in chat ID \(expectedMessage.chatId)")
                }
            }
        } catch {
            XCTFail("Error during test: \(error)")
        }
    }
}
