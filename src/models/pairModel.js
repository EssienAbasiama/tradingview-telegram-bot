class Pair {
    constructor(symbol) {
        this.symbol = symbol;
        this.crossEnabled = true;
        this.trendEnabled = true;
        this.volumeEnabled = true;
        this.fastMA = 10;
        this.slowMA = 21;
        this.crossTF = 'M5';
        this.trendTF1 = 'H1';
        this.trendTF2 = 'D1';
        this.lastCrossTime = null;
        this.lastTrendState = null;
    }
}

module.exports = Pair;
