function localize(s)
{
    // lol yeah, we'll do it properly when we can (ie. not just english style)
    rgx = /(\d+)(\d{3})/;
    while (rgx.test(s))
        s = s.replace(rgx, '$1'+','+'$2');
    return s;
}

var img;

function artist_got_info(xml)
{
    // Last.fm returns HTML, but no paragraph formatting :P
    bio = $('content', xml).text().replace(/(\n|\r)+/g, "<p>");
    // Don't open the URL inside the widget!
    bio = bio.replace(/(href=\")+(https?\:\/\/[^\s<>\"$]+)/ig, 'href="javascript:window.widget.openURL(\'$2\');return false;');
    document.getElementById('bio').innerHTML = bio;
    
    document.getElementById('listeners').innerText = localize($('listeners', xml).text()) + ' listeners';
    // this verbose syntax prevents jQuery selecting all the images of the 
    // similar artists as well :(
    var url = $("lfm", xml).children("artist").children("image[size='large']").text();
    url = url.replace('126', '252');

    img = new Image();
    img.onload = function() {
        var h = this.height;
        var back = document.getElementById('image');
        back.style.height = parseInt(h)+"px";
        back.style.backgroundImage='url('+this.src+')';
        window.resizeTo(286, h+34);
    }
    img.src = url;
}

function set_artist(scpt)
{
    artist = $.trim( scpt.outputString );
    artiste = document.getElementById('artist');
    if (artiste.innerText == artist) return;

    artiste.innerText = artist;
    document.getElementById('listeners').innerText = "";
    document.getElementById('image').style.backgroundImage='url()';

    artist = encodeURIComponent(artist);

    $.ajax( { url      : 'http://ws.audioscrobbler.com/2.0/?method=artist.getinfo&artist='+artist+'&api_key=b25b959554ed76058ac220b7b2e0a026',
              method   : 'get',
              dataType : 'xml',
              success  : artist_got_info
            } );
}

function show()
{
    window.widget.system('/usr/bin/osascript np.scpt', set_artist);
}

if (window.widget) {
    widget.onshow = show;
}
