
class Player {
    constructor(name, id) {
        this._name = name;
        this._id = id;
        this._hand = [];
    }

    get hand() {
        return this._hand;
    }

    get name() {
        return this._name;
    }

    sethand(cards) {
        this._hand = cards;
    }

    play(cards) {
        cards.forEach(card => {
            const index = this._hand.indexOf(card);
            if (index > -1) {
                this._hand.splice(index, 1)
            } else {
                console.log("ERROR : play card " + card.rank.shortName + (card.suit.unicode!=null?card.suit.unicode:"") + " which is not in player hand")
            }
        });
    }

    draw(card) {
        this._hand.push(card);
    }

    zapzap() {
        // TODO
    }


}

exports.Player = Player;