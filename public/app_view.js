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

function build_player_hand($container, id_player) {
    var deck = Deck(true);

    $.getJSON('/player/'+id_player+'/hand', function( data ) {
        
        deck.mount($container);
        for (var i = 54; i >= 0; i--) {
            var card = deck.cards[i];
            if (data.includes(i)){
                card.setSide('front');
            }
            else {
                card.unmount();
                deck.cards.splice(i, 1);
            }
        }
        //deck.sort();
        deck.fan();
    });
    return deck;
}

function build_topbar($topbar, player_deck) {
    var $sort = document.createElement('button')
    var $gethand = document.createElement('button')
    var $bysuit = document.createElement('button')
    var $fan = document.createElement('button')
    var $poker = document.createElement('button')
    var $flip = document.createElement('button')

    $gethand.textContent = 'GetHand'
    $sort.textContent = 'Sort'
    $bysuit.textContent = 'By suit'
    $fan.textContent = 'Fan'
    $poker.textContent = 'Poker'
    $flip.textContent = 'Flip'

    $topbar.appendChild($flip)
    $topbar.appendChild($gethand)
    $topbar.appendChild($bysuit)
    $topbar.appendChild($fan)
    $topbar.appendChild($poker)
    $topbar.appendChild($sort)


    $bysuit.addEventListener('click', function () {
        player_deck.sort(true) // sort reversed
        player_deck.bysuit()
    });

    $fan.addEventListener('click', function () {
        player_deck.fan()
    });

    $flip.addEventListener('click', function () {
        update_game()
    });
}