function build_player_table($container) {
    $.getJSON('/party', function( data ) {
        var $table = document.createElement('table');
        $container.appendChild($table);
        
        for (i=0; i<data.players.length; i++) {
            $table.insertRow($table.rows.length);
            $table.rows[i].insertCell($table.rows[i].cells.length);
            $table.rows[i].insertCell($table.rows[i].cells.length);
            $table.rows[i].cells[0].textContent = data.players[i].name;
            $table.rows[i].cells[1].textContent = data.players[i].nb_cards;
        }
    });
}

var game_deck = undefined;
var game_container;
var hand_deck;
var hand_container;
var hand_cards_id;
var player_id;

function build_game($container) {
    game_container = $container;
    return update_game();
}

function update_game() {
    console.log("update_game");
    if (game_deck!=undefined)
        game_deck.unmount();
    game_deck = Deck(true);
    
    $.getJSON('/game', function( data ) {
        var index_cards_back = 0;
        var nb_cards_front = 0;
        for (var i = 54; i >= 0; i--) {
            var card = game_deck.cards[i];
            if (data.cards_front.includes(i)){
                card.setSide('front');
                card.x = 40 + nb_cards_front*20;
                card.y = 0;
                card.$el.style.display = '';
                card.$el.style[Deck.prefix('transform')] = Deck.translate(card.x+'px', '0');
                nb_cards_front += 1;
                //console.log("Card "+i+" : front");
            } else if (index_cards_back<data.nb_card_back) {
                card.setSide('back');
                card.x = -40 -index_cards_back/2;
                card.y = -index_cards_back/2;
                card.$el.style.display = '';
                card.$el.style[Deck.prefix('transform')] = Deck.translate(card.x+'px', card.y+'px');
                index_cards_back += 1;
                //console.log("Card "+i+" : back");
            } else {
                card.unmount();
                //console.log("Card "+i+" : remove");
            }
        }
    });
    game_deck.mount(game_container);
    return game_deck;
}

function update_player_hand(cards_id) {
    if (hand_deck!=undefined) {
        hand_deck.unmount();
    }
    hand_deck = Deck(true);
    hand_deck.mount(hand_container);
    hand_cards_id = Array.from(cards_id);
    for (var i = 54; i >= 0; i--) {
        var card = hand_deck.cards[i];
        if (cards_id.includes(i)){
            card.setSide('front');
        }
        else {
            card.unmount();
            hand_deck.cards.splice(i, 1);
        }
    }
    hand_deck.fan();
}

function build_player_hand($container, id_player) {
    //hand_deck = Deck(true);
    hand_container = $container;
    player_id = id_player;

    $.getJSON('/player/'+id_player+'/hand', function( data ) {
        update_player_hand(data);
        //deck.sort();
        
    });
    return hand_deck;
}

function build_topbar($topbar, player_deck) {
    var $draw = document.createElement('button')
    var $play = document.createElement('button')
    var $bysuit = document.createElement('button')
    var $fan = document.createElement('button')
    var $poker = document.createElement('button')
    var $update = document.createElement('button')

    $play.textContent = 'Play'
    $draw.textContent = 'Draw'

    $bysuit.textContent = 'By suit'
    $fan.textContent = 'Fan'

    $poker.textContent = 'Poker'
    $update.textContent = 'Update'

    $topbar.appendChild($update)
    $topbar.appendChild($play)
    $topbar.appendChild($bysuit)
    $topbar.appendChild($fan)
    $topbar.appendChild($poker)
    $topbar.appendChild($draw)


    $bysuit.addEventListener('click', function () {
        hand_deck.sort(true) // sort reversed
        hand_deck.bysuit()
    });

    $fan.addEventListener('click', function () {
        hand_deck.fan()
    });



    $update.addEventListener('click', function () {
        update_game()
    });

    $play.addEventListener('click', function () {
        $.getJSON('/player/'+ player_id + '/play', { cards: [hand_cards_id[0]] })
        .done(function( json ) {
            update_player_hand(json);
        });
    });

    $draw.addEventListener('click', function () {
        $.getJSON('/player/'+ player_id + '/draw', { card: "deck" })
        .done(function( json ) {
            console.log("Draw : "+ json.draw);
            update_player_hand(json.hand);
        });
    });


}