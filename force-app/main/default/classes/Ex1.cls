@IsTest
public class Ex1 {
    @IsTest
    static void testCountOccurences(){
        List<String> testValues = new List<String>{'audi', 'BMW', 'Mercedes', 'Mercedes', 'audi', 'BMW','Toyota','BMW'};
        Map<String, Integer> expectedResult = Ex1.countOccurences(testValues);
      
     
        Assert.areEqual(1,expectedResult.get('audi'));
        Assert.areEqual(3,expectedResult.get('BMW'));
        Assert.areEqual(2,expectedResult.get('Mercedes'));
        Assert.areEqual(1,expectedResult.get('Toyota'));

        
    }


    public static Map<String ,Integer> countOccurences(List<String> values){
Map <String,Integer> result = new Map<String,Integer>();
for(String value: values){
    if(result.containsKey(value)){
        result.put(value ,result.get(value)+1);
    }else{
        result.put(value,1);
    }
}
return result;
    }
}