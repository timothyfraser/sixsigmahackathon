library(leaflet)
library(htmlwidgets)

m <- leaflet() %>%
  addTiles() %>%
  onRender("
    function(el, x) {
      var map = this;
      var container = map.getContainer();
      var canvas = document.createElement('canvas');
      canvas.style.position = 'absolute';
      canvas.style.top = '0';
      canvas.style.left = '0';
      canvas.style.pointerEvents = 'none';
      canvas.style.zIndex = '450';
      container.appendChild(canvas);

      function resize() {
        var size = map.getSize();
        canvas.width = size.x;
        canvas.height = size.y;
        draw();
      }

      function draw() {
        var ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        var pt = map.latLngToContainerPoint([27.95, -82.45]);
        ctx.beginPath();
        ctx.arc(pt.x, pt.y, 10, 0, 2*Math.PI);
        ctx.fillStyle = 'red';
        ctx.fill();
      }

      map.on('move', draw);
      map.on('zoom', draw);
      map.on('resize', resize);
      setTimeout(resize, 100);
    }
  ")
cat("Prototype built successfully\n")

