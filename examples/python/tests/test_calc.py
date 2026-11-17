import unittest

import calc


class CalcTest(unittest.TestCase):
    def test_add(self):
        """adds two numbers"""
        self.assertEqual(calc.add(1, 2), 3)

    def test_div(self):
        self.assertEqual(calc.div(6, 3), 2)

    def test_div_by_zero(self):
        """division by zero raises"""
        with self.assertRaises(ZeroDivisionError):
            calc.div(1, 0)


if __name__ == "__main__":
    unittest.main()
