import LooseweightKit

let db = FoodDatabase.shared
for q in ["grilled chicken breast", "basmati rice cooked", "pita bread", "tahini", "fried egg", "cucumber", "tomato raw", "lamb cooked", "cooked spaghetti", "greek salad", "dates", "arabic coffee", "orange juice", "white cheese", "falafel", "lentil soup", "fries"] {
    let r = db.search(q, limit: 4)
    print("\(q):")
    for x in r { print(String(format: "   %.2f  %@  (%.0f kcal)", x.score, x.record.name, x.record.per100g.kcal)) }
}
