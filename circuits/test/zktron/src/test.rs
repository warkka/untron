struct AdditionTest {
    a: i32,
    b: i32,
}

impl Test for AdditionTest {
    fn run(&self) {
        let result = self.a + self.b;
        println!("Addition Test: {} + {} = {}", self.a, self.b, result);
    }
}


struct MultiplicationTest {
    a: i32,
    b: i32,
}

impl Test for MultiplicationTest {
    fn run(&self) {
        let result = self.a * self.b;
        println!("Multiplication Test: {} * {} = {}", self.a, self.b, result);
    }
}
