// bubble_grid.js

svg.selectAll("*").remove();
d3.select("body").selectAll(".d3-tooltip").remove();

var width = width; 
var height = height; 
var numCols = 5; 
var rowHeight = 160;

var tooltip = d3.select("body").append("div")
    .attr("class", "d3-tooltip")
    .style("position", "absolute")
    .style("background", "white")
    .style("padding", "8px")
    .style("border", "1px solid #000")
    .style("border-radius", "5px")
    .style("pointer-events", "none") 
    .style("opacity", 1)
    .style("box-shadow", "2px 2px 6px rgba(84, 78, 78, 0.1)")
    .style("font-family", "sans-serif")
    .style("font-size", "12px");

var radiusScale = d3.scaleSqrt()
      .domain([0, d3.max(data, d => d.price)])
      .range([3, 20]);

var colorScale = d3.scaleOrdinal(d3.schemeCategory20);

var makes = [...new Set(data.map(d => d.make))].sort();
var centers = {};

makes.forEach((make, i) => {
    var col = i % numCols;
    var row = Math.floor(i / numCols);
    centers[make] = {
        x: (col * (width / numCols)) + (width / numCols / 2),
        y: (row * rowHeight) + 80 
    };
});

// 4. Force Simulation
var simulation = d3.forceSimulation()
    .nodes(data)
    .force('x', d3.forceX().strength(0.6).x(d => centers[d.make].x))
    .force('y', d3.forceY().strength(0.6).y(d => centers[d.make].y))
    .force('collide', d3.forceCollide().strength(0.9).radius(d => radiusScale(d.price) + 2))
    .force('charge', d3.forceManyBody().strength(-10));


var dragHandler = d3.drag()
    .on("start", function(d) {
        if (!d3.event.active) simulation.alphaTarget(0.3).restart();
        d.fx = d.x; 
        d.fy = d.y;
    })
    .on("drag", function(d) {
        d.fx = d3.event.x;
        d.fy = d3.event.y;
    })
    .on("end", function(d) {
        if (!d3.event.active) simulation.alphaTarget(0);
        d.fx = null; 
        d.fy = null;
    });

var nodes = svg.selectAll("circle")
    .data(data)
    .enter()
    .append("circle")
    .attr("r", d => radiusScale(d.price))
    .attr("fill", d => colorScale(d.make))
    .attr("stroke", "#fff")
    .attr("stroke-width", 1)
    .attr("opacity", 0.9)
    .call(dragHandler)
    
    // HOVER EVENTS
    .on("mouseover", function(d) {
        d3.select(this)
          .style("opacity", 0.5)
          .attr("stroke", "#333") 
          .attr("stroke-width", 2);

        tooltip.transition().duration(200).style("opacity", 0.9);
        tooltip.html(`
            <strong>${d.make} ${d.model}</strong><br/>
            Price: $${Math.round(d.price).toLocaleString()}<br/>
            Type: ${d.type}<br/>
            Origin: ${d.origin} <br/>
            Seating: ${d.seating}<br/>
            Engine Type: ${d.petrol}

        `)
        .style("left", (d3.event.pageX + 10) + "px")
        .style("top", (d3.event.pageY - 28) + "px");
    }) //reset
    .on("mouseout", function(d) {
        d3.select(this)
          .style("opacity", 0.9)
          .attr("stroke", "#fff")
          .attr("stroke-width", 1);
        tooltip.transition().duration(500).style("opacity", 0);
    });

// labels
var labels = svg.selectAll(".label-group")
    .data(makes)
    .enter()
    .append("g")
    .attr("transform", d => `translate(${centers[d].x}, ${centers[d].y + 60})`);

labels.append("rect")
    .attr("x", -50).attr("y", -15).attr("width", 100).attr("height", 25)
    .attr("fill", "#eee").attr("rx", 5);

labels.append("text")
    .text(d => d)
    .attr("text-anchor", "middle")
    .attr("dy", "0.35em")
    .style("font-family", "sans-serif")
    .style("font-size", "12px")
    .style("font-weight", "bold")
    .style("fill", "#333");

simulation.on("tick", () => {
    nodes
        .attr("cx", d => d.x)
        .attr("cy", d => d.y);
});