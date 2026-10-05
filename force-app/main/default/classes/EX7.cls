public with sharing class EX7 {
    public EX7() {
//todo 1:
Contact name1 = new Contact(LastName = 'Minkowitz');
//todo 2:
Contact name2 = new Contact(LastName = 'Singh');
//todo 3:
List<Contact> contacts = new List<Contact>();
//todo 4:
contacts.add(name1);
//todo 5:
contacts.add(name2);
//todo 6:
insert contacts;
//todo 7:
System.debug('The Id of name1: ' + name1.Id);
//todo 8:
System.debug('The Id of name2: ' + name2.Id);

    }
}