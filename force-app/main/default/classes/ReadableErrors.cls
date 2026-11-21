/**
 * A DmlException reaches the screen with no readable message, only its type,
 * so a trigger's own wording ("27AB... is not a valid GSTIN") would never be
 * seen. Screens' save methods catch it and rethrow this, which does show.
 */
public with sharing class ReadableErrors {

    public class ReadableException extends Exception {}

    public static ReadableException of(DmlException e) {
        return new ReadableException(e.getDmlMessage(0));
    }
}
