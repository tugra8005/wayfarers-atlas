// Reference runner for the original Atlas (github.com/savastakan/atlas @ 1748ccf).
// Main.java hard-codes "src/bbtas.kiss2.fsm"; this one takes the FSM path as an argument
// and prints the test suite, so the Lua port can be compared against it file by file.
public class RefMain {
    public static void main(String[] args) throws Exception {
        Graph graph = new Util().toGraph(args[0]);
        System.out.println(new Atlas().run(graph));
    }
}
